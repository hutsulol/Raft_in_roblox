-- QuestState.server.lua
-- Per-player quest state. Built up across C6 → C10:
--
--   C6 (this commit): DataStore + state cache + load / save / auto-save
--                     + read-only globals for the rest of the system.
--   C7: daily-roll on join.
--   C8: _G.OnQuestEvent generic objective hook.
--   C9: RemoteEvent (getState / track / untrack / startChallenge /
--       claimReward) handlers.
--   C10: _G.OnQuestResource shim so existing ResourceSpawner /
--        ShovelSystem / PickAxeSystem / FurnaceCraft callers still
--        feed the quest progress path.
--
-- State shape per player (extensible — every flow type the catalog
-- defines today fits this shape):
--   {
--     active = {
--       [questId] = {
--         progress = { N1, N2, ... }    -- one slot per objective; same
--                                       -- order as catalog.objectives
--         startedAt = os.time(),         -- challenges only; nil otherwise
--         tracked   = bool,              -- true when the player tracked
--                                       -- this quest in the menu (Phase H
--                                       -- shows the corner card for it).
--       }
--     },
--     permanentlyCompleted = { [questId] = true, ... },
--     pendingRewards       = { [questId] = true, ... }, -- waiting for claim
--     lastDailyDate        = N,                          -- os.date("*t").yday
--                                                         -- of the last roll
--     dailySelection       = { questId, questId, ... }, -- the 4 dailies
--                                                         -- chosen for today
--     historyLog           = { { id, completedAt }, ... }, -- newest first
--   }

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

-- Русские названия ресурсов — общий справочник на всю игру. Через pcall, потому
-- что квесты грузятся рано: без модуля награда просто покажет служебный ключ, а
-- не свалит выдачу целиком.
local ResourceNamesRu
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("ResourceNamesRu", 10))
	end)
	if ok then ResourceNamesRu = mod end
	if not ResourceNamesRu then
		warn("[QuestState] ResourceNamesRu не загрузился — награды покажут английские ключи")
	end
end

-- ═══ Studio: сбрасывать онбординг-квест при каждом входе ═══
-- Сейв разработчика уже держит onboarding_logs выполненным навсегда — список
-- квестов в Studio был бы вечно пуст. Со сбросом каждый заход в Studio показывает
-- полный цикл (трекер через 10с → 3 бревна → Claim → reveal). На игроков вне
-- Studio не влияет.
local RESET_ONBOARDING_IN_STUDIO = true

local AUTO_SAVE_INTERVAL = 120  -- seconds; matches DNAResearch / OnboardingState

-- ─── DataStore (defensive — Studio Play Solo without API access
-- still leaves us with a working in-memory cache, just no persistence).
local store
pcall(function()
	store = DataStoreService:GetDataStore("QuestState_v1")
end)

-- ─── State cache + dirty tracking ────────────────────────────────────
local states = {}    -- [player] = state table
local dirty  = {}    -- [player] = true when in-memory state has
-- diverged from the last persisted snapshot

-- Forward-declared so onQuestEvent (defined further down) can push
-- a snapshot to the client whenever progress changes. The actual
-- function body lives further down next to buildSnapshot — this
-- declaration is just a placeholder so the upvalue resolves.
local fireSnapshot

-- Coalesces multiple onQuestEvent calls in the same frame into a
-- single snapshot push. Without this, chopping 10 logs would push
-- 10 separate state events.
local snapshotPending = {}
local function schedulePush(player)
	if snapshotPending[player] then return end
	snapshotPending[player] = true
	task.defer(function()
		snapshotPending[player] = nil
		if states[player] and fireSnapshot then
			fireSnapshot(player)
		end
	end)
end

local function freshState()
	return {
		active               = {},   -- [questId] = { progress, startedAt, tracked }
		permanentlyCompleted = {},
		pendingRewards       = {},
		lastDailyDate        = 0,
		dailySelection       = {},
		historyLog           = {},
		-- ⚠️ КВЕСТЫ ПО СОБЫТИЮ ЖДУТ СВОЕГО ЧАСА, А НЕ ЛЕЖАТ В СПИСКЕ СРАЗУ.
		-- Сюжетные квесты выкладывались все разом, как только закрывался первый.
		-- Игрок начинал новую игру и видел три задания сразу, включая те, о
		-- которых он ещё ничего не знает («Ночлег» — до первой ночи, «Водолаз» —
		-- до того, как разбудил механика). Помеченные gated ждут, пока их не
		-- откроет свой триггер.
		unlocked             = {},   -- [questId] = true
	}
end

-- ── ЦЕПОЧКА ОНБОРДИНГА ──
-- Закрыл этот квест → сразу открывается следующий, а игрок слышит мысль о том,
-- зачем он ему. Держим одной таблицей: цепочку видно целиком, а не по кускам,
-- разбросанным вместе с триггерами. Объявлена ЗДЕСЬ, а не рядом с обработчиком
-- событий: сброс онбординга ниже берёт список звеньев из неё.
local CHAIN = {
	onboarding_logs = "onboarding_raft",
	onboarding_raft = "onboarding_beet",
	-- СТАРТОВЫЙ ОСТРОВ. Первое звено открывает не эта таблица, а
	-- StartIsleStory.server.lua в момент появления острова: до него квеста
	-- «дойди до острова» просто не существует. Дальше — обычная цепочка.
	startisle_scout = "startisle_cow",
	startisle_cow   = "startisle_meat",
	startisle_meat  = "startisle_paddle",
	-- ОСТРОВ-АВАНПОСТ. Первое звено открывает OutpostIsleStory в момент
	-- появления острова, последнее (архипелаг) — разговор с повстанцем: оба
	-- выдаются не по закрытию предыдущего, поэтому в таблице их нет.
	-- ⚠️ «ВЫЖЕЧЬ ЗАРАЗУ» НЕ СЛЕДУЕТ ЗА КРАФТОМ, И ЭТО НАМЕРЕННО.
	-- Между ними стоит заправка: механик заливает в собранный огнемёт первые
	-- полбака. Открой сжигание по цепочке — игрок получил бы задание жечь пустым
	-- баком, а разговор с механиком пришёл бы вдогонку. Квест открывает
	-- OutpostIsleStory в момент заправки.
	outpost_clear  = "outpost_flamer",
}

-- ⚠️ ЗВЕНЬЯ, КОТОРЫЕ НЕ ВЫДАЮТСЯ, ЕСЛИ ДЕЛО УЖЕ СДЕЛАНО.
-- Обычное звено, открытое с уже выполненными целями, просто висит заполненным:
-- события в прошлом не переиграть, а закрыть квест некому. Для «Чем грести» это
-- частый случай — весло могли собрать задолго до острова. Такое звено лучше не
-- выдавать вовсе: цепочка на нём и заканчивается, а игрок не получает задания
-- сделать то, что у него в рюкзаке. Разбор — в openNextInChain.
local SKIP_IF_ALREADY_DONE = {
	startisle_paddle = true,
}
local CHAIN_THOUGHT = {
	onboarding_logs = "RaftExpandThought",
	onboarding_raft = "BeetThought",
	-- сошёл на берег → увидел корову; убил корову → мясо сырое, нужен огонь;
	-- поел → пора отчаливать, а грести нечем
	startisle_scout = "StartIsleCowThought",
	startisle_cow   = "StartIsleMeatThought",
	startisle_meat  = "StartIsleFeastThought",
	-- перебил гарнизон → разглядел, что за частоколом растёт;
	-- собрал огнемёт → пора жечь
	outpost_clear  = "OutpostVirusThought",
	-- после крафта мысли нет: там говорит механик, и его реплику шлёт сценарий
	-- острова вместе с заправкой
}
-- ⚠️ КВЕСТЫ ЖИВОЙ СЦЕНЫ. У НИХ ДВА ОТЛИЧИЯ ОТ ОСТАЛЬНЫХ.
-- Их выдаёт мировое событие по своему расписанию, а не игрок своими действиями,
-- и цель у них стоит в мире — конкретный остров, конкретная корова. Отсюда:
--   1) пока сцена ИДЁТ, эксклюзив онбординга пускает такой квест рядом с собой
--      (спрятать его значило бы спрятать то, что прямо сейчас на экране);
--   2) пока сцены НЕТ — квест не показываем вовсе, даже открытым.
-- Второе не придирка. s.unlocked не сохраняется, но самолечение цепочки ВЫВОДИТ
-- его из сохранённого «предыдущее звено закрыто»: игрок, добравшийся вчера до
-- острова, на первом же снапшоте нового сервера получал открытую «Дикую корову»
-- — в мире, где нет ни острова, ни коровы, и событие kill:Cow неоткуда взяться.
-- Карточка висела невыполнимой весь забег.
-- Идёт ли сцена, знает флаг на Workspace: его ставит StartIsleStory, когда
-- остров уже стоит в мире, и живёт он ровно одну сессию сервера.
-- ⚠️ ЗНАЧЕНИЕ — ИМЯ ФЛАГА СВОЕЙ СЦЕНЫ, А НЕ ПРОСТО true.
-- Сцен стало две (стартовый остров и аванпост), и общий признак «какая-то сцена
-- идёт» пускал бы карточки стартового острова в мир, где стоит аванпост, — с
-- целями, которых там нет. Каждый квест спрашивает про СВОЙ остров.
local SCENE_QUESTS = {
	startisle_scout  = "StartIsleScene",
	startisle_cow    = "StartIsleScene",
	startisle_meat   = "StartIsleScene",
	outpost_clear    = "OutpostIsleScene",
	outpost_flamer   = "OutpostIsleScene",
	outpost_burn     = "OutpostIsleScene",
	outpost_islands  = "OutpostIsleScene",
}

-- идёт ли сцена этого квеста (без аргумента — идёт ли хоть какая-нибудь)
local function sceneRunning(questId)
	if questId then
		local flag = SCENE_QUESTS[questId]
		return flag ~= nil and workspace:GetAttribute(flag) == true
	end
	for _, flag in pairs(SCENE_QUESTS) do
		if workspace:GetAttribute(flag) == true then return true end
	end
	return false
end

-- «Квест сцены открыт»: выдан и не закрыт, либо закрыт, но награда не забрана —
-- иначе карточка «забери награду» за последнее звено исчезала бы в ту же
-- секунду, когда цепочка закрылась.
local function sceneQuestOpen(s, questId)
	-- квест чужой идущей сцены на экран не пускаем: его цели стоят на другом
	-- острове, и здесь их выполнить нечем
	if not sceneRunning(questId) then return false end
	return s.pendingRewards[questId] == true
		or (s.unlocked[questId] == true and not s.permanentlyCompleted[questId])
end

-- ⚠️ ЗВЕНЬЯ, КОТОРЫЕ ЖДУТ НАГРАДУ ЗА ПРЕДЫДУЩИЙ КВЕСТ.
-- Обычно следующий квест открывается сразу по закрытию целей — награда его не
-- держит и держать не должна. Но «Свой огород» — исключение по существу: сажать
-- нужно ту самую свёклу, которую дают в награду за расширение плота. Пока её не
-- забрали, у игрока её НЕТ, и мысль «Свёкла… съесть — и всё» звучала о предмете,
-- которого он в глаза не видел. Такие звенья открываются в момент клейма.
local CHAIN_AFTER_REWARD = {
	onboarding_raft = true,
}
-- ⚠️ КВЕСТ, К КОТОРОМУ ВОЗВРАЩАЕМСЯ, ЗАКРЫВ ВКЛИНИВШИЙСЯ.
-- «Пресную воду» открывает установка грядки (PlanterService): поливать посадки
-- нечем, пока нет очистителя. Это не звено цепочки, а отступление посреди неё —
-- закрыв его, игрок оставался с пустым трекером и стоящей сухой грядкой, хотя
-- вода у него теперь как раз есть. Возвращаем прерванный квест и объясняем, зачем
-- она была нужна.
local RESUME_AFTER = {
	onboarding_purifier = "onboarding_beet",
}
local RESUME_THOUGHT = {
	onboarding_purifier = "GardenWaterThought",
}

-- Полный сброс онбординг-квестов на новый цикл (Studio-тест).
-- ⚠️ ОТКАТЫВАЕМ ВСЮ ЦЕПОЧКУ, А НЕ ПАРУ ИМЁН СПИСКОМ.
-- Здесь перечислялись только «Первая древесина» и «Пресная вода», а «Расширение
-- плота» со «Своим огородом» оставались пройденными. После сброса игрок заново
-- добывал брёвна — и следующий квест не приходил вообще: цепочка видела, что он
-- уже открыт, и молчала. Когда добавилось самолечение цепочки, дыра поменяла вид
-- на «после брёвен сразу грядка»: пройденное «Расширение плота» открывало огород
-- через себя. Список звеньев берём из CHAIN, чтобы он больше не разъезжался с ней.
local ONBOARDING_CYCLE = { "onboarding_purifier" }   -- вне цепочки, но в том же цикле
for prevId, nextId in pairs(CHAIN) do
	table.insert(ONBOARDING_CYCLE, prevId)
	table.insert(ONBOARDING_CYCLE, nextId)
end

local function resetOnboarding(s)
	for _, id in ipairs(ONBOARDING_CYCLE) do
		s.permanentlyCompleted[id] = nil
		s.pendingRewards[id]       = nil
		-- запись прогресса не пересоздаём вручную: её длину знает только каталог,
		-- а вернут её самолечения в снапшоте
		s.active[id]               = nil
	end
	-- ⚠️ ЗАКРЫТОСТЬ СНИМАЕМ ТОЛЬКО У ЗВЕНЬЕВ ЦЕПОЧКИ.
	-- Их откроет заново закрытие предыдущего квеста. У ПЕРВОГО квеста unlocked
	-- трогать нельзя: его выдаёт разовая задача на 10-й секунде входа, второй раз
	-- она не сработает — список остался бы пустым навсегда. Очиститель открывает
	-- первая жажда, а она тоже одна на сессию.
	for _, nextId in pairs(CHAIN) do
		s.unlocked[nextId] = nil
	end
end
local STUDIO_RESET = RESET_ONBOARDING_IN_STUDIO and RunService:IsStudio()

-- Первый квест забега и через сколько секунд после входа он появляется.
local FIRST_QUEST_ID    = "onboarding_logs"
local FIRST_QUEST_DELAY = 10

-- ⚠️ КВЕСТ НАБИРАЕТ ПРОГРЕСС ТОЛЬКО ПОСЛЕ ВЫДАЧИ. ПРАВИЛО ОБЩЕЕ ДЛЯ ВСЕХ.
-- Активные записи создаются заранее — и дневным, и сюжетным, — а событий в игре
-- много и летят они постоянно. Из-за этого квест успевал ВЫПОЛНИТЬСЯ до того,
-- как его показали: «Первая древесина» закрывалась восстановленными при входе
-- брёвнами, «Ночлег» пришёл бы уже с готовым верстаком, «Пресная вода» — с
-- кружкой, скрафченной за час до первой жажды. Игрок открывает список и видит
-- задание, которое «уже сделано», хотя он его и не получал.
--
-- Считаем выданным:
--   • первый квест — после его паузы (unlocked ставит выдача);
--   • gated-квест  — когда открыл свой триггер;
--   • всё остальное (дневные, испытания) — сразу: их и выдают сразу.
local function isIssued(s, questId, def)
	if questId == FIRST_QUEST_ID then return s.unlocked[FIRST_QUEST_ID] == true end
	if def.gated then return s.unlocked[questId] == true end
	return true
end

-- ═══ НОВАЯ ИГРА = КВЕСТЫ С НУЛЯ ═══
-- Прогресс квестов привязан к ЗАБЕГУ, а не к аккаунту: новая игра начинается с
-- пустым плотом и пустым инвентарём, значит и сюжетная линия должна начинаться
-- заново. Раньше состояние грузилось из DataStore безусловно, и игрок, начавший
-- с нуля, видел все квесты уже выполненными — пройти их было нельзя.
--
-- Забег определяем по TeleportData из лобби: loadSave = «продолжить сохранение»,
-- его отсутствие = новая игра. Тот же флаг читает RaftSaveSystem, решая, грузить
-- плот или ставить стартовый, — так что решение всегда согласовано с плотом.
--
-- НЕ сбрасываем набор дневных заданий (dailySelection / lastDailyDate): он
-- привязан к календарю, а не к забегу. Иначе перезапуск игры превращался бы в
-- бесплатный реролл дневных.
-- ⚠️ ПРЯМОЙ ЗАХОД — ЭТО НОВАЯ ИГРА, А НЕ ПРОДОЛЖЕНИЕ.
-- Здесь раньше стояло обратное: без TeleportData состояние считалось
-- продолжением, «чтобы случайный вход не стирал прогресс». Но плот и инвентарь
-- при том же заходе уже стартуют с нуля (InventoryManager: «прямой заход =
-- новая игра», RaftSaveSystem ставит стартовый плот) — и квесты оставались
-- единственными, кто помнил прошлый забег. Выходило, что игрок начинает с
-- пустым рюкзаком и голым плотом, а сюжетные квесты у него уже пройдены и
-- пройти их заново нельзя.
-- Решение должно быть ОДНО на всю тройку, иначе они и дальше будут расходиться.
local function isNewRun(player)
	local ok, joinData = pcall(function() return player:GetJoinData() end)
	if not ok then return true end
	local td = joinData and joinData.TeleportData
	if type(td) ~= "table" then return true end   -- без лобби = новый забег
	return not td.loadSave
end

-- Сброс всего, что относится к ЗАБЕГУ. Активные записи дневных пересоздаются
-- ниже (seedDailyActiveEntries), сюжетные — в ensureStoryActiveEntries.
local function resetForNewRun(s)
	s.active               = {}
	s.permanentlyCompleted = {}
	s.pendingRewards       = {}
	s.historyLog           = {}
	-- новая игра = чистый лист: открытые по событию квесты снова закрыты
	s.unlocked             = {}
end

-- Идёт ли прямо сейчас GetAsync по этому игроку.
local loading = {}

local function loadState(player)
	if states[player] then return states[player] end

	-- ⚠️ ЗАГРУЗКА ОДНА НА ИГРОКА, И РЕЗУЛЬТАТ ПЕРВОЙ — ГЛАВНЫЙ.
	-- GetAsync ЖДЁТ, а проверка выше стоит до него: за время ожидания сюда успевал
	-- войти второй вызывающий (снапшот по запросу клиента приходит раньше, чем
	-- заканчивается загрузка на входе). Обе ветки доходили до конца, и ВТОРАЯ
	-- затирала состояние первой — вместе со сбросом «новой игры», уже к нему
	-- применённым. Прошлый забег возвращался целиком: в списке висел квест из
	-- старой игры, а «Первая древесина» значилась пройденной, пока её через десять
	-- секунд не выдавали силой.
	if loading[player] then
		while loading[player] and player.Parent do task.wait(0.05) end
		if states[player] then return states[player] end
	end
	loading[player] = true

	local loaded = freshState()

	if store then
		local ok, data = pcall(function()
			return store:GetAsync("Player_" .. player.UserId)
		end)
		if ok and type(data) == "table" then
			-- Sanitise every field so a malformed blob (older schema,
			-- corrupt write) can't propagate bad types into the rest
			-- of the system.
			if type(data.active) == "table" then
				for id, entry in pairs(data.active) do
					if type(id) == "string" and type(entry) == "table" then
						local progress = {}
						if type(entry.progress) == "table" then
							for i, n in ipairs(entry.progress) do
								progress[i] = tonumber(n) or 0
							end
						end
						loaded.active[id] = {
							progress  = progress,
							startedAt = tonumber(entry.startedAt),  -- may be nil
							tracked   = entry.tracked == true,
						}
					end
				end
			end
			if type(data.permanentlyCompleted) == "table" then
				for id, v in pairs(data.permanentlyCompleted) do
					if type(id) == "string" and v == true then
						loaded.permanentlyCompleted[id] = true
					end
				end
			end
			if type(data.pendingRewards) == "table" then
				for id, v in pairs(data.pendingRewards) do
					if type(id) == "string" and v == true then
						loaded.pendingRewards[id] = true
					end
				end
			end
			loaded.lastDailyDate = tonumber(data.lastDailyDate) or 0
			if type(data.dailySelection) == "table" then
				for i, id in ipairs(data.dailySelection) do
					if type(id) == "string" then
						loaded.dailySelection[i] = id
					end
				end
			end
			if type(data.historyLog) == "table" then
				for i, entry in ipairs(data.historyLog) do
					if type(entry) == "table"
						and type(entry.id) == "string"
						and type(entry.completedAt) == "number"
					then
						table.insert(loaded.historyLog, {
							id          = entry.id,
							completedAt = entry.completedAt,
						})
					end
				end
			end
		end
	end

	loading[player] = nil
	-- Пока мы ждали DataStore, состояние могли создать другой веткой. Она главнее:
	-- к ней уже успели применить сброс забега, а у нас на руках нетронутая копия
	-- прошлой игры. Свою — выбрасываем.
	if states[player] then return states[player] end

	states[player] = loaded
	return loaded
end

local function saveState(player)
	if not store then return end
	if not dirty[player] then return end
	local s = states[player]
	if not s then return end

	local ok = pcall(function()
		store:SetAsync("Player_" .. player.UserId, s)
	end)
	if ok then dirty[player] = nil end
end

local function markDirty(player)
	if states[player] then
		dirty[player] = true
	end
end

-- ─── Daily roll (C7) ────────────────────────────────────────────────
-- Called on player join. Compares os.date('*t').yday against the
-- player's saved lastDailyDate; if they differ, picks 4 fresh daily
-- ids from the catalog filtered against permanentlyCompleted (so
-- single-use crafting gates don't reappear) and clears any active
-- entries for the OLD daily ids so the new selection is the only
-- visible set on the Quests tab.
--
-- Story + challenge entries are unaffected — story is permanent, and
-- challenges are explicitly Started/Expired by the player so they
-- never spend a "daily slot".
local DAILIES_PER_DAY = 3
-- The catalog lives on _G.QuestCatalog (set by QuestCatalog.server.lua,
-- a sibling .server.lua so they should parse before this script for
-- alphabetical-folder-order reasons). Wait briefly + warn-fallback for
-- the rare load-order quirk.
local function waitForCatalog(timeoutSec)
	local deadline = os.clock() + (timeoutSec or 5)
	while os.clock() < deadline do
		if _G.QuestCatalog and _G.QuestCatalog.getByKind then
			return _G.QuestCatalog
		end
		task.wait(0.1)
	end
	return nil
end

local function rollDailiesIfNeeded(player)
	local s = states[player]
	if not s then return end

	local today = os.date("*t").yday
	if s.lastDailyDate == today and #s.dailySelection > 0 then
		-- Already rolled today; keep the same selection so progress
		-- across a relog mid-day doesn't reset.
		return
	end

	local catalog = waitForCatalog(5)
	if not catalog then
		warn("[QuestState] _G.QuestCatalog never appeared; skipping daily roll for "
			.. tostring(player.Name))
		return
	end

	-- Build the eligibility pool: every daily entry whose id isn't
	-- already in permanentlyCompleted. Workbench gate + future single-
	-- use crafting dailies fall out here automatically.
	local pool = {}
	for _, q in ipairs(catalog.getByKind("daily")) do
		if not s.permanentlyCompleted[q.id] then
			table.insert(pool, q.id)
		end
	end

	-- Shuffle (Fisher-Yates) so the same 4 don't cluster on
	-- consecutive days, then take the first N.
	for i = #pool, 2, -1 do
		local j = math.random(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end

	-- Drop any active entries from the previous day's daily set so
	-- only the new picks show on the Quests tab. Story + challenge
	-- active entries survive the swap.
	for _, oldId in ipairs(s.dailySelection) do
		s.active[oldId] = nil
		s.pendingRewards[oldId] = nil
	end

	s.dailySelection = {}
	for i = 1, math.min(DAILIES_PER_DAY, #pool) do
		local id = pool[i]
		table.insert(s.dailySelection, id)
		-- Seed an active entry with zero-filled progress per
		-- objective slot so the event hook in C8 has a target to
		-- increment without re-checking the catalog every tick.
		local def = catalog.get(id)
		if def then
			local progress = {}
			for objIdx = 1, #def.objectives do
				progress[objIdx] = 0
			end
			s.active[id] = {
				progress  = progress,
				startedAt = nil,
				tracked   = false,
			}
		end
	end

	s.lastDailyDate = today
	markDirty(player)
end

-- Пересоздать активные записи для УЖЕ ВЫБРАННЫХ на сегодня дневных.
-- Нужно после сброса под новую игру: набор дневных мы сохраняем (он
-- календарный), а обнулённые активные записи надо вернуть — иначе
-- rollDailiesIfNeeded увидит «сегодня уже роллили» и выйдет, а вкладка
-- квестов останется без дневных до следующих суток.
local function seedDailyActiveEntries(player)
	local s = states[player]
	if not s or #s.dailySelection == 0 then return end
	local catalog = waitForCatalog(5)
	if not catalog then return end

	for _, id in ipairs(s.dailySelection) do
		if not s.active[id] and not s.permanentlyCompleted[id] then
			local def = catalog.get(id)
			if def then
				local progress = {}
				for objIdx = 1, #def.objectives do
					progress[objIdx] = 0
				end
				s.active[id] = { progress = progress, startedAt = nil, tracked = false }
			end
		end
	end
	markDirty(player)
end

-- Story quests aren't part of the daily roll, but they DO need an
-- active entry on first sight so the event hook (C8) can match
-- objectives. This runs after the daily roll on first join + every
-- relog as a no-op.
local function ensureStoryActiveEntries(player)
	local s = states[player]
	if not s then return end
	local catalog = waitForCatalog(5)
	if not catalog then return end

	for _, q in ipairs(catalog.getByKind("story")) do
		if not s.permanentlyCompleted[q.id] and not s.active[q.id] then
			local progress = {}
			for objIdx = 1, #q.objectives do
				progress[objIdx] = 0
			end
			s.active[q.id] = {
				progress  = progress,
				startedAt = nil,
				tracked   = false,
			}
			markDirty(player)
		end
	end
end

-- Player-init helper that loadState calls into below.
local function initPlayerQuestState(player)
	loadState(player)

	-- НОВАЯ ИГРА — стираем прогресс забега ДО раскатки дневных и сюжетных:
	-- ниже они пересоздадутся с нулевым прогрессом, как при первом заходе.
	if states[player] and isNewRun(player) then
		resetForNewRun(states[player])
		markDirty(player)
		print("[QuestState] новая игра — квесты сброшены для " .. player.Name)
	end

	if STUDIO_RESET and states[player] then
		resetOnboarding(states[player])
		markDirty(player)
		print("[QuestState] Studio: онбординг-квест сброшен для " .. player.Name)
	end
	rollDailiesIfNeeded(player)
	seedDailyActiveEntries(player) -- вернуть дневные, если их снёс сброс
	ensureStoryActiveEntries(player)

	-- ⚠️ ПЕРВЫЙ КВЕСТ ВЫДАЁТСЯ ЧЕРЕЗ ПАУЗУ, А НЕ В МОМЕНТ ВХОДА.
	-- Две причины, и обе важны.
	--   1) Игрок только что появился и ещё смотрит по сторонам; задание,
	--      выскочившее в ту же секунду, он не читает.
	--   2) В первую секунду входа систему инвентаря пересобирают: восстановленные
	--      из прошлой сессии брёвна прилетали в квест как «добытые», и «Первая
	--      древесина» оказывалась ВЫПОЛНЕННОЙ ещё до старта — в списке было пусто.
	--      Пауза отделяет восстановление рюкзака от настоящей добычи.
	-- Прогресс на всякий случай обнуляем прямо здесь: если за эти секунды что-то
	-- всё же начислилось, оно не должно засчитаться.
	task.delay(FIRST_QUEST_DELAY, function()
		-- ⚠️ КАТАЛОГ ЖДЁМ, А НЕ СДАЁМСЯ ПРИ ЕГО ОТСУТСТВИИ.
		-- Здесь стоял `if not def then return end`: не успел загрузиться каталог —
		-- и игрок оставался БЕЗ ЕДИНОГО квеста до конца сессии, список пуст навсегда,
		-- второй попытки нет. Молчаливый отказ на пустом месте.
		local catalog = waitForCatalog(15)
		local s = states[player]
		if not s or not player.Parent then return end
		local def = catalog and catalog.get(FIRST_QUEST_ID)
		if not def then
			warn("[QuestState] каталог не поднялся — первый квест не выдан: " .. player.Name)
			return
		end
		-- ⚠️ ВЫДАЁМ СИЛОЙ, А НЕ «ЕСЛИ ЕЩЁ НЕ ПРОЙДЕН».
		-- Такая проверка здесь стояла и всё ломала: к десятой секунде квест уже
		-- значился пройденным (см. запрет начисления ниже), и выдача молча
		-- отменялась — список оставался пустым. Начало забега — это начало
		-- забега: чистим отметки и выдаём.
		s.permanentlyCompleted[FIRST_QUEST_ID] = nil
		s.pendingRewards[FIRST_QUEST_ID] = nil
		local progress = {}
		for i = 1, #def.objectives do progress[i] = 0 end
		s.active[FIRST_QUEST_ID] = { progress = progress, startedAt = nil, tracked = true }
		s.unlocked[FIRST_QUEST_ID] = true
		for id, e in pairs(s.active) do
			if id ~= FIRST_QUEST_ID then e.tracked = false end
		end
		markDirty(player)
		fireSnapshot(player)
		print("[QuestState] " .. player.Name .. ": выдан первый квест — " .. FIRST_QUEST_ID)
	end)
end

-- ─── Lifecycle hooks ─────────────────────────────────────────────────
Players.PlayerAdded:Connect(initPlayerQuestState)

Players.PlayerRemoving:Connect(function(player)
	saveState(player)
	states[player]  = nil
	dirty[player]   = nil
	loading[player] = nil   -- иначе ожидающая ветка зависла бы на вышедшем игроке
end)

-- Already-in-game players (live-reload / Studio Play Solo).
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(initPlayerQuestState, player)
end

task.spawn(function()
	while true do
		task.wait(AUTO_SAVE_INTERVAL)
		for player in pairs(states) do
			saveState(player)
		end
	end
end)

game:BindToClose(function()
	for player in pairs(states) do
		saveState(player)
	end
end)

-- ─── Generic event hook (C8) ────────────────────────────────────────
-- _G.OnQuestEvent(player, eventType, count) is the single entry point
-- for every gameplay system that wants to credit quest progress.
-- Each gameplay subsystem fires its own eventType string:
--   "resource:Log", "resource:Plastic", "resource:Stone", "resource:Leaves"
--   "pirate:kill", "pirate:bloodTaken"
--   "merc:hired", "dna:analyzed"
--   "crafted:Workbench", "crafted:WallPanel"
--   "planted:BerryBush"
-- The catalog declares which eventType each objective listens to;
-- this hook walks the player's active entries and bumps any matching
-- objective slot, marking permanentlyCompleted on quests that flip
-- all objectives to goal.
-- (CHAIN и CHAIN_THOUGHT объявлены выше, рядом со сбросом онбординга — он берёт
-- список звеньев из них.)

-- Мысль + карточка «Новый квест». Обе идут игроку, который его закрыл.
local function announceNext(player, def, thoughtKey)
	if thoughtKey and _G.StartDialogue then
		pcall(_G.StartDialogue, player, thoughtKey)
	end
	if _G.NotifyPlayer then
		_G.NotifyPlayer(player, {
			type = "info", icon = "📜",
			title = "Новый квест: " .. (def.title or ""),
			body = def.body,
		})
	end
end

-- Открыть следующее звено цепочки за закрывшимся квестом: поставить на трекер и
-- объявить. Одно место на оба вызова — по закрытию целей и по клейму награды
-- (см. CHAIN_AFTER_REWARD), чтобы они не разошлись поведением.
-- Возвращает true, если звено действительно открылось.
-- ⚠️ СОБЫТИЕ МОГЛО СЛУЧИТЬСЯ ДО ТОГО, КАК КВЕСТ ВЫДАЛИ.
-- События засчитываются только выданным квестам — иначе прогресс копился бы по
-- всему каталогу заранее. Но в туториале это давало тупик: игрок собирал молоток
-- раньше, чем открывался квест «Расширение плота», в логе появлялось
-- «crafted:Hammer НЕ засчитано никому», а потом задание вечно висело 0/1 с
-- молотком в руках. Переигрывать событие нельзя — его уже нет; зато можно
-- посмотреть на МИР: у крафта вещи доказательство — сама вещь в рюкзаке.
-- Поэтому при выдаче квеста цели вида crafted:<Предмет> проверяются по факту.
local function alreadyDone(player, eventType)
	local toolName = typeof(eventType) == "string" and eventType:match("^crafted:(.+)$")
	if not toolName then return 0 end
	for _, where in ipairs({ player.Character,
		player:FindFirstChildOfClass("Backpack"),
		player:FindFirstChild("StarterGear") }) do
		if where then
			for _, t in ipairs(where:GetChildren()) do
				if t:IsA("Tool") and t.Name == toolName then return 1 end
			end
		end
	end
	return 0
end

-- Стартовый прогресс квеста: нули плюс то, что игрок уже сделал до его выдачи.
local function freshProgress(player, def)
	local progress = {}
	for i, obj in ipairs(def.objectives) do
		progress[i] = math.min(alreadyDone(player, obj.eventType), obj.goal or 1)
	end
	return progress
end

local function openNextInChain(player, s, questId)
	local nextId = CHAIN[questId]
	if not nextId or s.unlocked[nextId] then return false end
	local catalog = _G.QuestCatalog
	local nextDef = catalog and catalog.get(nextId)
	if not nextDef then return false end

	local progress = freshProgress(player, nextDef)

	-- ⚠️ ЗВЕНО, ЧЬИ ЦЕЛИ УЖЕ ВЫПОЛНЕНЫ, НЕ ВЫДАЁМ ВОВСЕ (см. SKIP_IF_ALREADY_DONE).
	-- freshProgress выше уже посмотрел на мир и мог заполнить цели целиком — так
	-- бывает, когда предмет собрали задолго до квеста. Выдать такой квест значит
	-- повесить игроку задание 1/1, которое некому закрыть: события в прошлом не
	-- переиграть. Пропускаем и сразу помечаем пройденным, иначе самолечение
	-- цепочки в снапшоте будет открывать его заново на каждом кадре.
	-- Мысль при этом ВСЁ РАВНО играем: она закрывает предыдущий квест, а не
	-- открывает этот, и без неё сцена оборвалась бы на полуслове.
	local allDone = true
	for i, obj in ipairs(nextDef.objectives) do
		if (progress[i] or 0) < (obj.goal or 1) then allDone = false break end
	end

	if SKIP_IF_ALREADY_DONE[nextId] then
		if allDone then
			s.permanentlyCompleted[nextId] = true
			markDirty(player)
			local thoughtKey = CHAIN_THOUGHT[questId]
			if thoughtKey and _G.StartDialogue then
				pcall(_G.StartDialogue, player, thoughtKey)
			end
			print(("[QuestState] %s: «%s» пропущен — цели уже выполнены")
				:format(player.Name, nextId))
			return false
		end
	end

	--[[ ⚠️ ЦЕЛИ ВЫПОЛНЕНЫ ЕЩЁ ДО ВЫДАЧИ — ЗАКРЫВАЕМ СРАЗУ, А НЕ ВЕШАЕМ 1/1.
     Прогресс копится только у ВЫДАННОГО квеста, а прибавка идёт лишь пока
     current < goal. Значит звено, открытое уже заполненным, закрыть нечем:
     повторный крафт не поможет, награда не станет доступной, следующее звено
     не откроется. Ровно так вставал «Огнемёт»: рецепт доступен с первого дня,
     а квест приходит только на третий — собравший огнемёт заранее получал
     карточку «1/1» навсегда.
     Пропускать звено (SKIP_IF_ALREADY_DONE) тут не годится: игрок ДЕЙСТВИТЕЛЬНО
     сделал работу и должен получить награду. Поэтому выдаём его сразу закрытым —
     карточка приходит в состоянии «забери награду», как при обычном выполнении. ]]
	if allDone then
		s.unlocked[nextId] = true
		for _, other in pairs(s.active) do other.tracked = false end
		s.active[nextId] = { progress = progress, startedAt = nil, tracked = false }
		s.pendingRewards[nextId] = true
		if nextDef.permanent then s.permanentlyCompleted[nextId] = true end
		markDirty(player)
		announceNext(player, nextDef, CHAIN_THOUGHT[questId])
		schedulePush(player)
		print(("[QuestState] %s: «%s» выдан сразу закрытым — цели были выполнены заранее")
			:format(player.Name, nextId))
		return true
	end

	s.unlocked[nextId] = true
	-- ⚠️ ОТСЛЕЖИВАЕМЫЙ КВЕСТ РОВНО ОДИН.
	-- Здесь новая запись просто получала tracked = true, а с остальных флаг никто
	-- не снимал. Клиент берёт ПЕРВЫЙ tracked из списка — и это мог оказаться старый
	-- квест, а не только что выданный: трекер показывал одно, подсказка вела другое,
	-- баннеры двух подсказок налезали друг на друга. _G.TrackQuest снимает флаг со
	-- всех и делает это правильно — делаем так же.
	for _, other in pairs(s.active) do other.tracked = false end
	s.active[nextId] = { progress = progress, startedAt = nil, tracked = true }
	announceNext(player, nextDef, CHAIN_THOUGHT[questId])
	return true
end

--[[ ⚠️ ОБЩИЕ ШАГИ: МИР ОДИН НА ВСЕХ, ЗНАЧИТ И ЗАСЧИТЫВАТЬ НАДО ВСЕМ.
     Прогресс всегда считался ТОЛЬКО тому, кто вызвал событие. Для «собери 3
     бревна» это верно — брёвна лежат в его рюкзаке. А для гарнизона аванпоста
     это тупик: пиратов двое, одного убил хозяин, второго друг — у каждого 1 из
     2, и квест не закрывается НИКОГДА. Убить больше некого: гарнизон кончился.
     То же самое со всем, что существует в единственном экземпляре на весь
     плот — корова стартового острова, монолит, очиститель, поле заразы.
     Поэтому у шага появился признак shared. Стоит он ровно там, где цель —
     объект мира, а не содержимое рюкзака: крафт и сбор ресурсов остаются
     личными, иначе друг скрафтил кружку, а квест закрылся у обоих, и пить
     второму не из чего.
     ⚠️ РАЗДАЁМ ТОЛЬКО ОБЩИЕ ШАГИ, А НЕ ВСЁ ПОДРЯД. Соседу засчитывается
     исключительно то, что он сам пометил общим: иначе событие «убей корову»
     закрыло бы у него же личный шаг другого квеста, слушающий то же имя. ]]
local function creditPlayer(player, eventType, count, onlyShared)
	if not player or typeof(eventType) ~= "string" or eventType == "" then return end
	count = (type(count) == "number" and count > 0) and count or 1

	local s = states[player]
	if not s then
		warn(("[QuestState] событие %s пришло, но состояния игрока %s нет")
			:format(eventType, player.Name))
		return
	end
	local catalog = _G.QuestCatalog
	if not catalog then
		warn("[QuestState] событие " .. eventType .. " пришло до загрузки каталога")
		return
	end

	local stateChanged = false
	-- ДИАГНОСТИКА: событие пришло, но ни один квест его не ждал. Молчаливый
	-- пропуск — самый частый способ «квест не засчитался»: причин ровно три, и
	-- увидеть их можно только отсюда. Убрать, когда цепочка отстоится.
	local credited = false

	for questId, entry in pairs(s.active) do
		local def = catalog.get(questId)
		if def and isIssued(s, questId, def) and not s.permanentlyCompleted[questId] then
			local allDone = true
			local touched = false
			for objIdx, obj in ipairs(def.objectives) do
				local current = entry.progress[objIdx] or 0
				-- соседу — только помеченные общими шаги (см. комментарий выше)
				local mine = (obj.eventType == eventType)
					and (not onlyShared or obj.shared == true)
				if mine and current < obj.goal then
					-- Challenge expiry guard — if this is a timed
					-- quest and the timer has already elapsed,
					-- silently drop the increment (the player just
					-- ran out of time on a kill / chop swing). The
					-- expiry sweep elsewhere clears the entry; we
					-- just don't credit progress past it here.
					if def.kind == "challenge" and entry.startedAt
						and (os.time() - entry.startedAt) > (def.durationSec or 0)
					then
						-- expired
					else
						local new = math.min(obj.goal, current + count)
						if new ~= current then
							entry.progress[objIdx] = new
							touched = true
							credited = true
							print(("[QuestState] %s: %s → %s %d/%d")
								:format(player.Name, eventType, questId, new, obj.goal))
						end
					end
				end
				if (entry.progress[objIdx] or 0) < obj.goal then
					allDone = false
				end
			end

			if touched then
				stateChanged = true
				if allDone then
					-- Mark the reward as claimable. Permanent quests
					-- (story + single-use dailies like the workbench
					-- gate) also flip permanentlyCompleted so the
					-- daily roll never reissues them. Non-permanent
					-- dailies stay claimable until the next roll
					-- swaps them out anyway.
					s.pendingRewards[questId] = true
					if def.permanent then
						s.permanentlyCompleted[questId] = true
					end
					-- Auto-untrack on completion (T10) so the corner
					-- tracker card slides out cleanly. The menu's
					-- card flips to "Claim Reward" off rewardPending,
					-- which doesn't depend on tracked, so claiming
					-- still works from any tab.
					entry.tracked = false

					-- ⚠️ ЦЕПОЧКА ОНБОРДИНГА СВЯЗЫВАЕТСЯ ЗДЕСЬ, А НЕ ТАЙМЕРОМ.
					-- Следующий квест выдаётся ровно в момент закрытия
					-- предыдущего: игрок дочитывает мысль и сразу видит, что
					-- делать дальше. Отдельный наблюдатель за «выполнен ли
					-- первый» был бы вторым источником правды о цепочке.
					-- Звенья с пометкой CHAIN_AFTER_REWARD ждут клейма: их квест
					-- требует предмет, который выдаётся наградой (свёкла).
					if not CHAIN_AFTER_REWARD[questId] then
						openNextInChain(player, s, questId)
					end

					-- Возврат к прерванному квесту (см. RESUME_AFTER): вода добыта —
					-- значит грядку теперь есть чем полить.
					local resumeId = RESUME_AFTER[questId]
					local resumeEntry = resumeId and s.active[resumeId]
					if resumeEntry and s.unlocked[resumeId]
						and not s.permanentlyCompleted[resumeId] then
						for _, other in pairs(s.active) do other.tracked = false end
						resumeEntry.tracked = true
						if RESUME_THOUGHT[questId] and _G.StartDialogue then
							pcall(_G.StartDialogue, player, RESUME_THOUGHT[questId])
						end
					end
				end
			end
		end
	end

	-- ⚠️ СОБЫТИЕ, КОТОРОЕ НИКУДА НЕ ПОПАЛО, — НЕ НОРМА, А СИМПТОМ.
	-- «Квест не засчитался» выглядит одинаково при трёх разных причинах: квест не
	-- открыт (gated без unlocked), у него нет активной записи, или цель ждёт другую
	-- строку события. Раньше все три молчали. Печатаем только для сюжетных строк —
	-- ресурсы летят постоянно и засорили бы вывод.
	if not credited and (eventType:match("^built:") or eventType:match("^crafted:")
		or eventType:match("^planted:") or eventType:match("^purifier:")) then
		local waiting = {}
		local catalogRef = catalog
		for questId, entry in pairs(s.active) do
			local def = catalogRef.get(questId)
			if def and not s.permanentlyCompleted[questId] then
				for i, obj in ipairs(def.objectives) do
					if obj.eventType == eventType then
						table.insert(waiting, ("%s[выдан=%s %d/%d]"):format(
							questId, tostring(isIssued(s, questId, def)),
							entry.progress[i] or 0, obj.goal))
					end
				end
			end
		end
		print(("[QuestState] %s: событие %s НЕ засчитано никому. Ждали его: %s")
			:format(player.Name, eventType,
				(#waiting > 0) and table.concat(waiting, ", ") or "никто"))
	end

	if stateChanged then
		markDirty(player)
		-- Push the new state to the client so the menu's progress bars
		-- update live. schedulePush coalesces multiple events in the
		-- same frame into one snapshot.
		schedulePush(player)
	end
end

--[[ Есть ли вообще в каталоге общий шаг с таким событием. Ответ не меняется за
     сессию, поэтому считаем один раз на имя события: раздача по всем игрокам
     стоит дороже самой проверки, и делать её вслепую на каждое бревно незачем. ]]
local sharedEventCache = {}
local function isSharedEvent(eventType)
	local hit = sharedEventCache[eventType]
	if hit ~= nil then return hit end

	local catalog = _G.QuestCatalog
	if not (catalog and catalog.all) then return false end   -- каталог ещё не поднялся: не кэшируем

	local found = false
	for _, def in pairs(catalog.all()) do
		for _, obj in ipairs(def.objectives or {}) do
			if obj.shared == true and obj.eventType == eventType then
				found = true
				break
			end
		end
		if found then break end
	end
	sharedEventCache[eventType] = found
	return found
end

--[[ ⚠️ ЕДИНСТВЕННЫЙ ВХОД ДЛЯ ВСЕХ СИСТЕМ — И ОН ЖЕ РАЗДАЁТ ОБЩЕЕ.
     Тому, кто событие вызвал, засчитывается всё как раньше. Остальным на плоту
     — только шаги с пометкой shared. Списка «кто на плоту» здесь нет намеренно:
     сервер поднимается под одну компанию (лобби резервирует его на пати), так
     что все игроки сервера и есть эта компания. ]]
local function onQuestEvent(player, eventType, count)
	creditPlayer(player, eventType, count, false)

	if not isSharedEvent(eventType) then return end
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			creditPlayer(other, eventType, count, true)
		end
	end
end

_G.OnQuestEvent = onQuestEvent

-- ─── _G.OnQuestResource shim (C10) ──────────────────────────────────
-- Existing gameplay systems (ResourceSpawner, ShovelSystem,
-- PickAxeSystem, FurnaceCraft) already call _G.OnQuestResource on
-- every harvest. DailyQuests + ChopTreesFlow have prior claims on
-- the same global, so we chain instead of overwrite — capture the
-- previous hook inside task.defer (which fires after every
-- ServerScriptService script's top-level body has parsed regardless
-- of folder order), then route every call through both the previous
-- chain and our generic _G.OnQuestEvent("resource:"..resType) hook.
task.defer(function()
	local previous = _G.OnQuestResource
	_G.OnQuestResource = function(player, resType, amount)
		if typeof(previous) == "function" then
			-- pcall isolates a buggy peer (DailyQuests' progress
			-- table corruption, ChopTreesFlow's onboarding bookkeeping)
			-- so a downstream error doesn't break our own credit path.
			pcall(previous, player, resType, amount)
		end
		if typeof(resType) == "string" and resType ~= "" then
			pcall(onQuestEvent, player, "resource:" .. resType, amount or 1)
		end
	end
end)

-- ─── RemoteEvent + handlers (C9) ────────────────────────────────────
-- One channel for every menu/tracker → server quest action. Server
-- replies with snapshots that bake in the catalog data the client
-- needs to render (titles, body, icon, reward) so the client never
-- has to require the catalog itself — keeps quest content swappable
-- without a client redeploy.
local event = ReplicatedStorage:FindFirstChild("QuestState")
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "QuestState"
	event.Parent = ReplicatedStorage
end

-- ─── Challenge expiry sweep (F1) ────────────────────────────────────
-- Called before each snapshot so the client never sees a stale
-- "still running" challenge whose timer has actually run out. If the
-- elapsed time exceeds durationSec AND the goal isn't hit, we reset
-- the entry (clear startedAt, zero progress, drop tracked) so the
-- card flips back to its "Start" state. Completed challenges leave
-- startedAt set so the player can claim — the daily-roll handler
-- below cleans them up on the next day.
local function sweepExpiredChallenges(player)
	local s = states[player]
	if not s then return end
	local catalog = _G.QuestCatalog
	if not catalog then return end

	local now = os.time()
	for id, entry in pairs(s.active) do
		local def = catalog.get(id)
		if def and def.kind == "challenge" and entry.startedAt then
			local elapsed = now - entry.startedAt
			if elapsed > (def.durationSec or 0) then
				-- Did the player hit every goal before the timer expired?
				local allDone = true
				for i, obj in ipairs(def.objectives) do
					if (entry.progress[i] or 0) < obj.goal then
						allDone = false
						break
					end
				end
				if not allDone and not s.pendingRewards[id] then
					-- Expired without a win → reset for retry.
					entry.startedAt = nil
					entry.tracked   = false
					for i = 1, #def.objectives do
						entry.progress[i] = 0
					end
					markDirty(player)
				end
			end
		end
	end
end

-- Build a defensive snapshot the client can render directly. Each
-- visible-to-player quest goes in once, with display fields baked
-- in alongside the player's progress so the menu has everything
-- needed to paint a card without follow-up server calls.
local function buildSnapshot(player)
	sweepExpiredChallenges(player)
	local s = states[player] or loadState(player)
	local catalog = _G.QuestCatalog
	if not catalog then
		return { quests = {}, pendingRewards = {}, historyLog = {} }
	end

	-- ⚠️ САМОЛЕЧЕНИЕ ЦЕПОЧКИ ОНБОРДИНГА.
	-- Следующее звено открывается ОДНИМ событием — в момент закрытия предыдущего
	-- (см. CHAIN в onQuestEvent). Стоит этот момент пропустить, и звено теряется
	-- НАВСЕГДА: gated-квест без unlocked скрыт, а «закрой предыдущий» второй раз уже
	-- не случится. Пропустить его легко — s.unlocked НЕ СОХРАНЯЕТСЯ (loadState знает
	-- только про permanentlyCompleted и pendingRewards), так что любой перезаход по
	-- продолжению забега стирал открытость, оставляя закрытым предыдущий квест.
	-- Именно так пропадало «Расширение плота».
	-- Здесь то же правило выводится ИЗ СОСТОЯНИЯ: предыдущий закрыт → следующий
	-- открыт. Событие продолжает работать как было — оно просто перестало быть
	-- единственным носителем этого знания.
	for prevId, nextId in pairs(CHAIN) do
		-- Звено с пометкой CHAIN_AFTER_REWARD считается «созревшим» только когда
		-- награда за предыдущий квест ЗАБРАНА: иначе лечение открыло бы его сразу
		-- по выполнению целей и обошло бы саму отсрочку.
		local prevDone = s.permanentlyCompleted[prevId]
			and not (CHAIN_AFTER_REWARD[prevId] and s.pendingRewards[prevId])
		-- ⚠️ ТУ ЖЕ ПРОВЕРКУ «УЖЕ СДЕЛАНО», ЧТО И В openNextInChain.
		-- Лечение открывает звено по состоянию, а не по событию, и без этой
		-- проверки оно возвращало бы пропущенный квест на каждом снапшоте: игрок
		-- с веслом в рюкзаке получал «сделай весло» 1/1, которое некому закрыть.
		local skipDone = false
		if prevDone and SKIP_IF_ALREADY_DONE[nextId] then
			local nextDef = catalog.get(nextId)
			if nextDef then
				skipDone = true
				for _, obj in ipairs(nextDef.objectives) do
					if alreadyDone(player, obj.eventType) < (obj.goal or 1) then
						skipDone = false
						break
					end
				end
				if skipDone then
					s.permanentlyCompleted[nextId] = true
					markDirty(player)
				end
			end
		end
		if prevDone and not skipDone and not s.unlocked[nextId]
			and not s.permanentlyCompleted[nextId] and not s.pendingRewards[nextId] then
			s.unlocked[nextId] = true
			-- Запись прогресса нужна, чтобы событийный хук вообще увидел квест:
			-- он ходит по s.active. На входе её создаёт ensureStoryActiveEntries,
			-- но лечение может случиться и посреди сессии.
			if not s.active[nextId] then
				local nextDef = catalog.get(nextId)
				if nextDef then
					s.active[nextId] = { progress = freshProgress(player, nextDef),
						startedAt = nil, tracked = false }
				end
			end
			markDirty(player)
		end
	end

	local quests = {}

	local function pushQuest(def, activeEntry)
		local objectives = {}
		for i, obj in ipairs(def.objectives) do
			objectives[i] = {
				eventType = obj.eventType,
				goal      = obj.goal,
				label     = obj.label,
				progress  = (activeEntry and activeEntry.progress[i]) or 0,
			}
		end
		local secondsRemaining
		if def.kind == "challenge" and activeEntry and activeEntry.startedAt then
			local elapsed = os.time() - activeEntry.startedAt
			secondsRemaining = math.max(0, (def.durationSec or 0) - elapsed)
		end
		table.insert(quests, {
			id               = def.id,
			kind             = def.kind,
			title            = def.title,
			body             = def.body,
			icon             = def.icon,
			reward           = def.reward,
			durationSec      = def.durationSec,
			objectives       = objectives,
			tracked          = (activeEntry and activeEntry.tracked) == true,
			startedAt        = activeEntry and activeEntry.startedAt,
			secondsRemaining = secondsRemaining,
			completed        = s.permanentlyCompleted[def.id] == true,
			rewardPending    = s.pendingRewards[def.id] == true,
		})
	end

	-- ── ОНБОРДИНГ: пока первый квест (3 бревна из океана) не закрыт, список состоит
	-- ТОЛЬКО из него, и он ПРИНУДИТЕЛЬНО отслеживается — карточка в меню и HUD-трекер
	-- подсвечены с первой секунды, игроку сразу видно, что квест выполняется.
	-- (Даже если клиент пришлёт untrack, следующий снапшот вернёт отслеживание.)
	--
	-- ⚠️ ЗДЕСЬ БОЛЬШЕ НЕТ STUDIO-СБРОСА ПОСРЕДИ СЕССИИ, И ЭТО НАРОЧНО.
	-- Он стоял ровно тут: «оба онбординг-квеста закрыты и награды забраны → начать
	-- цикл заново, чтобы тестировать без перезапуска». Условие достижимо обычной
	-- игрой — и в ту же секунду, когда игрок забирал награду за воду, весь онбординг
	-- обнулялся у него на руках: пройденные квесты слетали, «Первая древесина»
	-- снова становилась невыполненной. Пока цепочка была из двух квестов, это
	-- выглядело безобидно; теперь их пятеро, и сброс сносит живой прогресс.
	-- Сброс остался ТОЛЬКО на входе (initPlayerQuestState) — каждый запуск Studio и
	-- так начинает онбординг заново, а посреди забега его трогать нечем.
	local obDef = catalog.get("onboarding_logs")
	local ob_completed = obDef and s.permanentlyCompleted["onboarding_logs"] == true
		local ob_pending   = obDef and s.pendingRewards["onboarding_logs"] == true
		-- ⚠️ ЭКСКЛЮЗИВ ОТСТУПАЕТ ПЕРЕД КВЕСТОМ ОТ МИРОВОГО СОБЫТИЯ.
		-- Пока «Первая древесина» не закрыта, список показывает ТОЛЬКО её — чтобы
		-- новичок не тонул в заданиях. Но сцену со стартовым островом выдаёт не
		-- игрок, а расписание: остров всплывает на второй день независимо от того,
		-- выловил ли игрок три бревна. Под эксклюзивом происходило вот что —
		-- катсцена играет, мысль звучит, квест на сервере выдан и КОПИТ прогресс,
		-- а в меню и на трекере по-прежнему «Собери брёвна». Сцена шла вслепую.
		-- Особенно наглядно в Studio: там онбординг сбрасывается на каждом входе,
		-- то есть при тесте кнопкой остров всегда попадал в этот случай.
		-- Отступаем только перед перечисленными: остальным гейтам эксклюзив нужен.
		-- ⚠️ СНАЧАЛА СПРАШИВАЕМ МИР, И ТОЛЬКО ПОТОМ АНКЕТУ ИГРОКА.
		-- Отступать эксклюзиву есть смысл ровно тогда, когда сцена ИДЁТ на этом
		-- сервере. По одному состоянию квестов это не определить, и вот почему:
		-- s.unlocked не сохраняется, зато самолечение цепочки выше ВЫВОДИТ его из
		-- сохранённого permanentlyCompleted предыдущего звена. То есть игрок,
		-- закрывший «Землю по курсу» вчера, на первом же снапшоте нового сервера
		-- получал открытую «Дикую корову» — и эксклюзив выключался у него с нуля
		-- секунды, в мире, где остров всплывёт только минут через десять, а то и
		-- вовсе не всплывёт. Флаг на Workspace живёт одну сессию сервера и
		-- поднимается ровно в момент подъёма острова (StartIsleStory), поэтому
		-- перетечь из прошлого забега он не может.
		--
		-- Незабранная награда тоже держит эксклюзив отступившим: permanent-квест
		-- попадает в permanentlyCompleted СРАЗУ по выполнению целей, и без этой
		-- половины условия карточка «забери награду» за последнее звено исчезала
		-- бы в ту же секунду, когда цепочка закрылась.
		local worldQuestOpen = false
		if sceneRunning() then
			for questId in pairs(SCENE_QUESTS) do
				if sceneQuestOpen(s, questId) then
					worldQuestOpen = true
					break
				end
			end
		end
		-- показываем, пока квест НЕ завершён-и-заклеймлен: свежий / в процессе / ждёт
		-- награды. Раньше гейт был только `not completed`, и застрявшее состояние
		-- «выполнен + ждёт награды» прятало квест НАСОВСЕМ (список в бете был пуст).
		-- ⚠️ ДО ВЫДАЧИ ПЕРВОГО КВЕСТА СПИСОК ПУСТ, И ЭТО НАРОЧНО.
		-- Он появляется через FIRST_QUEST_DELAY секунд после входа (см.
		-- initPlayerQuestState). Без этой проверки ветка ниже показывала бы его
		-- сразу же, и пауза ничего бы не значила.
		if obDef and not s.unlocked["onboarding_logs"]
			and not ob_completed and not ob_pending then
			-- ещё не выдан: ничего не показываем
		elseif obDef and not ob_completed and not ob_pending then
		-- ⚠️ ЭКСКЛЮЗИВ ДЕРЖИТСЯ ТОЛЬКО ПОКА ЦЕЛИ НЕ ЗАКРЫТЫ, А НЕ ДО КЛЕЙМА НАГРАДЫ.
		-- Раньше сюда попадало и состояние «выполнен, но награда не забрана»
		-- (ob_pending), и список схлопывался до одного квеста. Цепочка при этом уже
		-- открыла следующий на сервере — а снапшот его не отдавал, и выглядело так,
		-- будто новый квест ждёт, когда заберут награду за старый. Связи между ними
		-- нет и не должно быть: как только цели закрыты, ветка ниже отдаёт и карточку
		-- «забери награду», и новый квест разом.
		--
		-- самолечение: если активной записи нет — создаём тут же, чтобы квест ВСЕГДА
		-- рисовался (не зависим от тайминга ensureStoryActiveEntries)
		local entry = s.active["onboarding_logs"]
		if not entry then
			entry = { progress = { 0 }, startedAt = nil, tracked = false }
			s.active["onboarding_logs"] = entry
		end
		-- ⚠️ ЭКСКЛЮЗИВ НЕ ОТМЕНЯЕТСЯ, А ПУСКАЕТ РЯДОМ ОДНУ КАРТОЧКУ.
		-- Первый заход был другим: при живой сцене условие ветки становилось
		-- ложным и игрок проваливался в обычный режим целиком — вместе с ним
		-- вылезали «Ночлег» и «Пресная вода», которые эксклюзив прячет намеренно
		-- (их триггеры срабатывают как раз к этому времени: первая ночь уже
		-- прошла). Список у новичка прыгал с одной карточки на три. Правильно —
		-- пустить рядом ТОЛЬКО квест идущей сцены: её выдал не игрок, а мир, и
		-- спрятать её значит спрятать то, что прямо сейчас на экране.
		--[[ СЮЖЕТ ТОРГОВЦА — ТОЖЕ «ВЫДАЛ МИР». Торговец приплывает на 3-й день, и к
		     этому времени «Первое дерево» может быть ещё не закрыто (особенно после
		     перемотки дня): квест «поставь подарок» прятался за эксклюзивом, хотя
		     уже засчитывался. Пускаем открытые сюжетные квесты рядом, как сцену. ]]
		local storyTracked = false
		for _, id in ipairs({ "story_fishing_place", "story_assign_fisher", "story_farm_build", "story_tavern_build" }) do
			local d = catalog.get(id)
			if d and s.unlocked[id] and (not s.permanentlyCompleted[id] or s.pendingRewards[id]) then
				pushQuest(d, s.active[id])
				if s.active[id] and s.active[id].tracked then storyTracked = true end
			end
		end
		if storyTracked then
			-- трекер у сюжета (его поставил _G.TrackQuest) — не отбираем
		elseif worldQuestOpen then
			-- трекер отдаём сцене: его уже переставила цепочка (openNextInChain),
			-- и принудительная простановка здесь отобрала бы его обратно
			for questId in pairs(SCENE_QUESTS) do
				local sceneDef = catalog.get(questId)
				if sceneDef and sceneQuestOpen(s, questId) then
					pushQuest(sceneDef, s.active[questId])
				end
			end
		elseif not s.untrackedByUser then
			-- ⚠️ ИГРОК СНЯЛ С ОТСЛЕЖИВАНИЯ РУКАМИ — НЕ ВОЗВРАЩАЕМ (владелец).
			-- Снапшот принудительно ставил онбординг на трекер каждый раз, и кнопка
			-- «Отслеживается» в меню ничего не делала: карточка возвращалась
			-- следующим же снапшотом. Флаг снимает «track» из меню.
			entry.tracked = true
		end
		pushQuest(obDef, entry)
	else
		-- обычный режим (онбординг закрыт): сюжет + ежедневные + испытания

		-- ── ОНБОРДИНГ #2 (Fresh Water): самолечение активной записи +
		-- автотрекинг.
		-- ⚠️ ТОЛЬКО ПОСЛЕ ПЕРВОЙ ЖАЖДЫ.
		-- Раньше квест вставал на трекер сразу, как закрывался First Timber, — и
		-- игрок с полной шкалой воды получал задание про очиститель ни с того ни с
		-- сего. Открывает его ThirstThought, когда пить действительно хочется.
		local purDef = catalog.get("onboarding_purifier")
		if purDef and s.unlocked["onboarding_purifier"]
			and (not s.permanentlyCompleted["onboarding_purifier"]
			or s.pendingRewards["onboarding_purifier"]) then
			local entry = s.active["onboarding_purifier"]
			if not entry then
				local progress = {}
				for i = 1, #purDef.objectives do progress[i] = 0 end
				entry = { progress = progress, startedAt = nil, tracked = false }
				s.active["onboarding_purifier"] = entry
			end
			if not s.pendingRewards["onboarding_purifier"] then
				local anyTracked = false
				for _, e in pairs(s.active) do
					if e.tracked then anyTracked = true; break end
				end
				if not anyTracked and not s.untrackedByUser then
					entry.tracked = true
				end
			end
		end

		-- Story quests are visible until permanently completed AND claimed.
		-- Гейт `or pendingRewards` — тот же фикс, что у онбординга выше:
		-- permanent-квест попадает в permanentlyCompleted СРАЗУ по выполнению
		-- целей, и без этого условия карточка «забери награду» исчезала бы.
		for _, def in ipairs(catalog.getByKind("story")) do
			-- ⚠️ КВЕСТ ПО СОБЫТИЮ ПОКАЗЫВАЕМ ТОЛЬКО ПОСЛЕ ЕГО СОБЫТИЯ.
			-- Иначе игрок с самого начала видит «Ночлег» и «Водолаза», хотя ночь
			-- ещё не наступала и механик не разбужен. Открывает их свой триггер
			-- (BedThought / DiverQuestWatcher) — он же и ставит на трекер.
			local hidden = def.gated and not s.unlocked[def.id]
				and not s.permanentlyCompleted[def.id] and not s.pendingRewards[def.id]
			-- ⚠️ КВЕСТ СЦЕНЫ БЕЗ САМОЙ СЦЕНЫ НЕ ПОКАЗЫВАЕМ.
			-- Открытым он может оказаться и на сервере, где острова нет и не было:
			-- самолечение цепочки выводит открытость из сохранённого «предыдущее
			-- звено закрыто». Цель такого квеста стоит в мире, которого здесь нет,
			-- — карточка была бы невыполнимой (см. SCENE_QUESTS).
			if SCENE_QUESTS[def.id] and not sceneRunning(def.id) then hidden = true end
			if not hidden
				and (not s.permanentlyCompleted[def.id] or s.pendingRewards[def.id]) then
				pushQuest(def, s.active[def.id])
			end
		end
		-- Today's daily picks (the C7 selection).
		for _, id in ipairs(s.dailySelection) do
			local def = catalog.get(id)
			if def and not s.permanentlyCompleted[def.id] then
				pushQuest(def, s.active[def.id])
			end
		end
		-- Every challenge is always visible (Phase F handles Start/expire).
		for _, def in ipairs(catalog.getByKind("challenge")) do
			pushQuest(def, s.active[def.id])
		end
	end

	-- History payload: copy ids + completedAt only. Client maps the
	-- ids against the same catalog field info if it wants display
	-- titles for past quests — for now the server includes them.
	local history = {}
	for i, entry in ipairs(s.historyLog) do
		local def = catalog.get(entry.id)
		history[i] = {
			id          = entry.id,
			completedAt = entry.completedAt,
			title       = def and def.title,
			icon        = def and def.icon,
			reward      = def and def.reward,
		}
	end

	-- ДИАГНОСТИКА (бета): что реально уходит клиенту. Если quests=0 — квест не
	-- построился (проверь onboarding-флаги / каталог). Убрать после проверки.
	if not _G.__questSnapDbgOff then
		local ob = catalog.get("onboarding_logs")
		print(("[QuestState] snapshot → quests=%d | onboarding: def=%s completed=%s pending=%s active=%s")
			:format(#quests, tostring(ob ~= nil),
				tostring(s.permanentlyCompleted["onboarding_logs"] == true),
				tostring(s.pendingRewards["onboarding_logs"] == true),
				tostring(s.active["onboarding_logs"] ~= nil)))
	end

	return {
		quests         = quests,
		pendingRewards = s.pendingRewards,
		historyLog     = history,
	}
end

function fireSnapshot(player)
	event:FireClient(player, "state", buildSnapshot(player))
end

-- Helper used by track / untrack / startChallenge / claimReward.
-- ⚠️ ТРЕКЕР МОЖНО СТАВИТЬ И С СЕРВЕРА.
-- Действие "track" приходит от клиента, и серверным системам (например,
-- DiverQuestWatcher, который сам решает, когда выдать квест про водолаза)
-- пользоваться им было нечем: послать клиенту его же запрос — значит ничего не
-- сделать. Ручка делает ровно то же, что обработчик события.
-- ⚠️ ВЗЯТЬ НА ТРЕКЕР = ОТКРЫТЬ.
-- Оба триггера (мысль про кровать, наблюдатель за водолазом) именно этим и
-- сообщают «пора». Отдельного «unlock» заводить незачем: квест, который начали
-- отслеживать, по определению уже показан игроку.
_G.TrackQuest = function(player, questId)
	local s = states[player]
	if not s or typeof(questId) ~= "string" then return false end
	s.unlocked[questId] = true
	local entry = s.active[questId]
	if not entry then
		-- записи прогресса нет (квест добавлен в каталог позже, чем игрок зашёл, или
		-- её не создали на входе) — заводим, иначе квест молча не появлялся на трекере
		local def = _G.QuestCatalog and _G.QuestCatalog.get(questId)
		if not def or s.permanentlyCompleted[questId] then return false end
		entry = { progress = freshProgress(player, def), startedAt = nil, tracked = false }
		s.active[questId] = entry
	end
	for _, other in pairs(s.active) do other.tracked = false end
	entry.tracked = true
	markDirty(player)
	fireSnapshot(player)
	return true
end

local function getActiveEntry(player, questId)
	local s = states[player]
	if not s then return nil, nil end
	local entry = s.active[questId]
	local def   = _G.QuestCatalog and _G.QuestCatalog.get(questId)
	return entry, def, s
end

event.OnServerEvent:Connect(function(player, action, ...)
	if typeof(action) ~= "string" then return end

	if action == "getState" then
		-- Self-heal: if the player's state never recorded a successful
		-- roll for today (lastDailyDate stuck on a previous day, or 0
		-- because the catalog-load race meant the first PlayerAdded
		-- roll silently dropped), retry now. We DON'T re-roll just
		-- because dailySelection is empty same-day — that's the legit
		-- "claimed all 4 dailies, wait for tomorrow" state and we
		-- don't want infinite quest farming.
		local s = states[player]
		if s and s.lastDailyDate ~= os.date("*t").yday
			and #s.dailySelection == 0
		then
			rollDailiesIfNeeded(player)
		end
		-- Same self-heal for story quests: if the catalog-load race
		-- meant the first ensureStoryActiveEntries silently skipped,
		-- the story entries never got seeded, and gameplay hooks
		-- like crafted:WorkBench / crafted:WallPanel had nothing to
		-- credit progress against. Calling it again here is a no-op
		-- once the entries already exist (T11).
		ensureStoryActiveEntries(player)
		fireSnapshot(player)

	elseif action == "track" then
		-- One quest tracked at a time — clear any previous tracked
		-- flag, then flip the new one. Phase H's tracker card subscribes
		-- to the snapshot to know which quest to display.
		local questId = (select(1, ...))
		if typeof(questId) ~= "string" then return end
		local entry, def, s = getActiveEntry(player, questId)
		if not entry or not def then return end
		-- клиентские триггеры (мысль про кровать) открывают квест этим же запросом
		s.unlocked[questId] = true
		s.untrackedByUser = nil
		for _, other in pairs(s.active) do other.tracked = false end
		entry.tracked = true
		markDirty(player)
		fireSnapshot(player)

	elseif action == "untrack" then
		local s = states[player]
		if not s then return end
		s.untrackedByUser = true   -- см. снапшот: принудительный трекинг онбординга выключен
		for _, other in pairs(s.active) do other.tracked = false end
		markDirty(player)
		fireSnapshot(player)

	elseif action == "startChallenge" then
		local questId = (select(1, ...))
		if typeof(questId) ~= "string" then return end
		local s = states[player]
		if not s then return end
		local def = _G.QuestCatalog and _G.QuestCatalog.get(questId)
		if not def or def.kind ~= "challenge" then return end

		-- Challenges aren't seeded at init time the way story / dailies
		-- are — the player picks which one to engage with by clicking
		-- Start. If there's no active entry yet, create one here so
		-- the rest of the handler has somewhere to write progress.
		local entry = s.active[questId]
		if not entry then
			local progress = {}
			for i = 1, #def.objectives do progress[i] = 0 end
			entry = { progress = progress, startedAt = nil, tracked = false }
			s.active[questId] = entry
		end

		if entry.startedAt then return end -- already running

		entry.startedAt = os.time()
		-- Reset progress so a relogged challenge starts clean.
		for i = 1, #def.objectives do
			entry.progress[i] = 0
		end
		-- Auto-track started challenges so the corner card shows up
		-- immediately (per the spec: timed quests jump to tracking).
		for _, other in pairs(s.active) do other.tracked = false end
		entry.tracked = true
		markDirty(player)
		fireSnapshot(player)

	elseif action == "claimReward" then
		local questId = (select(1, ...))
		if typeof(questId) ~= "string" then return end
		local s = states[player]
		if not s or not s.pendingRewards[questId] then return end
		local def = _G.QuestCatalog and _G.QuestCatalog.get(questId)
		if not def then return end

		-- Grant the reward via the existing inventory pipeline.
		-- Resource rewards route through _G.AddResourceToInventory
		-- (used by ResourceSpawner / FurnaceCraft for the same
		-- inventory-full overflow handling); item rewards fall back
		-- to the same path with the item's name string.
		if def.reward and def.reward.kind and def.reward.name then
			local fn = _G.AddResourceToInventory
			if typeof(fn) == "function" then
				pcall(fn, player, def.reward.name, def.reward.count or 1, nil)
			else
				warn("[QuestState] _G.AddResourceToInventory not available; reward dropped")
			end

			-- Экранная анимация выдачи (RewardReveal.client): предмет впрыгивает с
			-- отскоком, иконка предмета вместо глифа-заглушки ⚔.
			local revealEv = ReplicatedStorage:FindFirstChild("RewardReveal")
			if revealEv then
				-- ⚠️ ПЕРЕВОД БЕРЁМ ИЗ ОБЩЕГО СПРАВОЧНИКА, А НЕ ИЗ СВОЕГО СПИСКА.
				-- Здесь лежала местная табличка на четыре ресурса, и всё остальное
				-- вываливалось игроку служебным ключом — «BEET x2» вместо «СВЁКЛА x2».
				-- Такие копии обречены отставать от каталога: ResourceNamesRu для того
				-- и заведён, чтобы перевод жил в одном месте.
				local RES_ICON = {
					Log     = "rbxassetid://116178347748793",
					Leaves  = "rbxassetid://96691360298069",
					Compost = "rbxassetid://78760258555926",
					Plastic = "rbxassetid://132919988751848",
					Stone   = "rbxassetid://96450657403376",
					Beet    = "rbxassetid://80108091374305",
				}
				local rw = def.reward
				local base = rw.label or (ResourceNamesRu and ResourceNamesRu(rw.name))
					or rw.name or "ПРЕДМЕТ"
				revealEv:FireClient(player, {
					name = string.upper(base) .. " x" .. tostring(rw.count or 1),
					icon = rw.icon or RES_ICON[rw.name] or "",
				})
			end
		end

		-- Bookkeeping: remove from pending, append to history,
		-- clear the active slot for daily quests so the card flips
		-- to "claimed" and clears on next roll. Story / single-use
		-- dailies stay in permanentlyCompleted from the C8 hook.
		s.pendingRewards[questId] = nil

		-- Награда в руках — теперь можно открывать звено, которое её ждало.
		-- Именно здесь появляется «Свой огород»: свёклу, которую он просит
		-- посадить, игрок получил секунду назад.
		if CHAIN_AFTER_REWARD[questId] then
			openNextInChain(player, s, questId)
		end

		table.insert(s.historyLog, 1, { id = questId, completedAt = os.time() })
		-- Cap the history at 50 entries so the DataStore blob stays
		-- small over a long-running save file.
		while #s.historyLog > 50 do
			table.remove(s.historyLog)
		end
		if def.kind == "daily" then
			s.active[questId] = nil
			-- Drop the slot from today's selection too so the card
			-- actually disappears for the rest of the day instead of
			-- re-appearing with 0/N progress on the next snapshot.
			-- The remaining 1-3 dailies stay visible; the slot is not
			-- back-filled — players can grind out the others or wait
			-- for tomorrow's roll.
			for i = #s.dailySelection, 1, -1 do
				if s.dailySelection[i] == questId then
					table.remove(s.dailySelection, i)
				end
			end
		end
		markDirty(player)
		saveState(player)
		fireSnapshot(player)
	end
end)

-- Push a snapshot once initPlayerQuestState has finished so the
-- client controller's getState round-trip isn't the only path that
-- delivers state. Wrap in task.spawn so we don't block the join
-- handler chain.
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		-- Wait one tick so initPlayerQuestState (also bound to
		-- PlayerAdded) finishes before we snapshot.
		task.wait(0)
		fireSnapshot(player)
	end)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(fireSnapshot, player)
end

-- ─── Read-only globals ───────────────────────────────────────────────
-- Other server scripts can read state via these accessors. Mutations
-- always go through helpers (added in C7-C9) so the dirty flag stays
-- accurate.
_G.GetQuestState     = function(player) return states[player] or loadState(player) end
_G.MarkQuestDirty    = markDirty
_G.SaveQuestState    = saveState
_G.QuestStateEvent   = event
_G.SnapshotQuestState = buildSnapshot