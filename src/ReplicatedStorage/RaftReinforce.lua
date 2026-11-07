local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	УКРЕПЛЁННЫЙ ПОЛ — одна точка правды для сервера, клиента и загрузки сейва.

	Укрепление НЕ ставит новый тайл: берётся уже стоящая доска пола и ей меняются
	меш с текстурой. Клетка, сварка и координаты остаются те же — значит ничего не
	ломается ни в решётке, ни в сейве.

	Признак укрепления — атрибут TileKind = "iron" на тайле. Тем же атрибутом
	отличается сеть ("net"), и RaftSaveSystem уже сохраняет его как floors.kind,
	так что укрепление переживает перезаход без правок формата сейва.
]]

local AssetService = game:GetService("AssetService")

local RaftReinforce = {}

RaftReinforce.MESH      = "rbxassetid://124784781651606"
RaftReinforce.TEXTURE   = "rbxassetid://115361262411959"
RaftReinforce.KIND      = "iron"
RaftReinforce.COST      = 1        -- ВРЕМЕННАЯ цена, по договорённости
RaftReinforce.COST_TYPE = "Log"

-- ── ЗВУК УКРЕПЛЕНИЯ ──────────────────────────────────────────────────────────
-- ПЕРЕКЛЮЧАТЕЛЬ — SOUND_PICK: номер варианта из SOUND_VARIANTS. Менять можно
-- прямо здесь, а можно вживую: в режиме стройки клавиша M проигрывает следующий
-- вариант и печатает его номер с названием в консоль. Понравившийся номер вписать
-- сюда — и он останется навсегда.
--
-- Поля варианта:
--   label  — как он называется в консоли при переборе;
--   sound  — имя УЖЕ СУЩЕСТВУЮЩЕГО Sound в SoundService (ищется рекурсивно,
--            клонируется, оригинал не трогаем);
--   id     — либо вместо sound: прямой SoundId;
--   pitch  — PlaybackSpeed: ниже 1 = тяжелее и глуше;
--   volume — громкость;
--   start  — сколько секунд ИСХОДНИКА пропустить (TimePosition). Нужен, когда в
--            начале файла тишина: замедление тоном её растягивает, и удар начинает
--            опаздывать. Секунды считаются по исходнику, поэтому на слух пауза
--            уходит длиннее: 0.08 при pitch 0.4 — это 0.2 с задержки.
--
-- ⚠️ ПРОВЕРЕНО НА ПРАКТИКЕ: rbxasset://sounds/metal.ogg в клиенте НЕТ (звук молча
-- уходил к следующему кандидату), а unsheath.mp3 — это вынимаемый меч, не годится.
-- Оба выброшены, повторно их не подставлять.
RaftReinforce.SOUND_FOLDER = "Building"
RaftReinforce.SOUND_NAME   = "Reinforce"   -- свой звук: SoundService.Building.Reinforce
RaftReinforce.SOUND_VOLUME = 0.7           -- если у варианта не задана своя громкость

RaftReinforce.SOUND_PICK = 4   -- «Глухой клац» — выбран по итогам перебора

RaftReinforce.SOUND_VARIANTS = {
	{ label = "Камень, как было",      sound = "Rock_Crush",  pitch = 1.0,  volume = 0.7 },
	{ label = "Камень ниже — плита",   sound = "Rock_Crush",  pitch = 0.55, volume = 0.85 },
	{ label = "Лязг щеколды",          id = "rbxasset://sounds/switch3.wav",          pitch = 0.65, volume = 0.85 },
	-- start срезает тишину в начале файла: на pitch 0.4 она звучала как 0.2 с паузы
	{ label = "Глухой клац",           id = "rbxasset://sounds/clickfast.wav",        pitch = 0.4,  volume = 0.9, start = 0.08 },
	{ label = "Металлический звон",    id = "rbxasset://sounds/electronicpingshort.wav", pitch = 0.5, volume = 0.6 },
	{ label = "Доска ниже — брус",     sound = "Place_Block", pitch = 0.55, volume = 0.85 },
	{ label = "Свой звук Reinforce",   sound = "Reinforce",   pitch = 1.0,  volume = 0.8 },
}

-- Меши настила — единственное, что мы подменяем. Имя строгое: у сети, причала и
-- прочих построек меши называются иначе, и трогать их нельзя.
local function floorMeshes(tile)
	local out = {}
	local function consider(d)
		if d:IsA("MeshPart") and d.Name:lower():find("^raft_floor") then
			table.insert(out, d)
		end
	end
	consider(tile)
	for _, d in ipairs(tile:GetDescendants()) do consider(d) end
	return out
end

function RaftReinforce.hasFloorMesh(tile)
	return #floorMeshes(tile) > 0
end

-- Доска пола, которую можно укрепить.
-- ⚠️ ОПОЗНАЁМ ПО МЕШУ, А НЕ ПО ИМЕНИ И НЕ ПО BuildType: центральная доска плота —
-- это сам PrimaryPart, у неё нет ни имени Raft_part, ни атрибутов, и по прежнему
-- правилу центр плота не укреплялся вообще. Меш настила есть у всех досок и только
-- у них, поэтому проверка одна и работает везде.
function RaftReinforce.isFloorTile(child)
	if child:GetAttribute("DockSteps") then return false end          -- причал
	if child.Name == "Net_Part" then return false end                 -- сеть
	if child:GetAttribute("TileKind") == "net" then return false end
	-- пол второго этажа: тот же меш настила, но это не доска плота — не укрепляется
	if child:GetAttribute("BuildType") == "floor_upper" or child.Name == "Raft_floor_upper" then return false end
	return RaftReinforce.hasFloorMesh(child)
end

function RaftReinforce.isReinforced(child)
	return child:GetAttribute("TileKind") == RaftReinforce.KIND
end

function RaftReinforce.canReinforce(child)
	return RaftReinforce.isFloorTile(child) and not RaftReinforce.isReinforced(child)
end

-- ⚠️ MeshId у MeshPart во время игры НЕ присваивается — он только для чтения.
-- Штатный путь: AssetService:CreateMeshPartAsync + ApplyMesh. Функция ЙИЛДИТ.
local function swapMesh(part)
	local ok, fresh = pcall(function()
		return AssetService:CreateMeshPartAsync(RaftReinforce.MESH, {
			CollisionFidelity = part.CollisionFidelity,
			RenderFidelity = part.RenderFidelity,
		})
	end)
	if ok and fresh then
		-- ApplyMesh тянет за собой и размер нового меша, а тайл обязан остаться
		-- размером с клетку — возвращаем свой Size обратно.
		local size = part.Size
		local applied = pcall(function() part:ApplyMesh(fresh) end)
		part.Size = size
		if applied then return true end
	end
	return (pcall(function() part.MeshId = RaftReinforce.MESH end))
end

-- Делает тайл укреплённым: новый меш, новая текстура, метка TileKind.
-- ЙИЛДИТ (грузит ассет), поэтому на сервере вызывать в отдельном потоке.
function RaftReinforce.apply(tile)
	local parts = floorMeshes(tile)
	for _, part in ipairs(parts) do
		-- SurfaceAppearance перекрывает TextureID целиком: пока он висит на детали,
		-- новая текстура не появится вообще.
		for _, d in ipairs(part:GetChildren()) do
			if d:IsA("SurfaceAppearance") then d:Destroy() end
		end
		swapMesh(part)
		part.TextureID = RaftReinforce.TEXTURE
		-- Молча провалившийся ассет выглядит как «механика не работает» — пусть
		-- лучше будет строчка в логе с конкретной деталью.
		if part.MeshId ~= RaftReinforce.MESH then
			warn(("[Укрепление] меш не подменился у %s (MeshId остался %s)")
				:format(part:GetFullName(), tostring(part.MeshId)))
		end
	end
	tile:SetAttribute("TileKind", RaftReinforce.KIND)
	return #parts > 0
end

return RaftReinforce
