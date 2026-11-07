--[[
	ТАВЕРНА (IslandHall) — дом создания жителей. Хендофф IslandHall_Integration_V25
	(D:\Roblox\test\IslandHall_Integration_V25).

	Сервер: IslandHallService.server (таймер, выдача), уровни — общая система
	построек (BuildingLevels / BuildingUpgradeServer). Клиент: IslandHallClient
	(интерьер, работники, двери, сфера, сборка жителя, табличка на алтаре).

	⚠️ ВСЁ ДВИЖУЩЕЕСЯ — НА КЛИЕНТЕ, ОТ ТОЧКИ AssemblyOrigin. Здание приварено к
	плоту; сервер не двигает в нём ни одной детали (иначе плот пересобирался бы
	и дёргался). Каждый кадр клиент ставит свою «сцену» от текущего положения
	AssemblyOrigin — плот плывёт и поворачивает, сцена едет вместе с ним.
]]

local C = {}

C.NAME = "IslandHall"          -- имя шаблона, тула и постройки на плоту
C.WORKER = "IslandHallWorker"  -- R6 работников (одобренная внешность)
C.TAG = "IslandHall"           -- тег постройки (ставит сервер)

-- игровые сутки = день 380 с + ночь 120 с (DayNightCircle)
C.DAY_SECONDS = 500
-- подготовка жителя по уровню здания: 2 дня, 1,5, 1, 1
C.RECRUIT_DAYS = { [0] = 2, [1] = 1.5, [2] = 1, [3] = 1 }
function C.cycleSeconds(level)
	return (C.RECRUIT_DAYS[math.clamp(level or 0, 0, 3)] or 2) * C.DAY_SECONDS
end

-- кого выдаёт таверна: веса шансов (Роза 5★ — реже, пират Билли 3★ — чаще).
-- Тех, кто уже в команде, таверна пропускает (IslandHallService.pickResident)
C.RESIDENTS = { { def = "rose", weight = 1 }, { def = "pirate", weight = 3 } }

-- тайминг появления (одинаковый у сервера и клиентов, считается от RevealStartedAt)
C.OPEN = 0.85            -- двери разогнались, жителя ещё не видно
C.PART = 0.65            -- перелёт энергии к части тела
C.PART_GAP = 0.22        -- пауза после материализации
C.PARTS = { "Left Leg", "Right Leg", "Torso", "Left Arm", "Right Arm", "Head" }
C.AFTER = 0.35           -- пауза между сборкой и выходом
C.CELEBRATE = 2.8        -- радость у выхода
C.EXIT_FROM = Vector3.new(0, 2.4, -0.8)
C.EXIT_TO = Vector3.new(0, 2.4, -8.5)
C.SCALE = 0.78           -- работники и житель

function C.partStart(i) return C.OPEN + (i - 1) * (C.PART + C.PART_GAP) end
function C.assembledAt() return C.partStart(#C.PARTS) + C.PART + C.PART_GAP end
function C.walkStart() return C.assembledAt() + C.AFTER end

--[[ Локальные файлы хендоффа (ASSET_MANIFEST.json). rbxasset:// работает ТОЛЬКО в
     Studio на этом компьютере — игрокам в опубликованной игре их нет. Загрузи
     файлы из D:\Roblox\test\IslandHall_Integration_V25\Assets от владельца игры
     и впиши сюда rbxassetid — код берёт published, если он есть. ]]
C.ASSETS = {
	OrbTexture   = { localUri = "rbxasset://textures/AltarOrb/orb.jpg", published = "rbxassetid://123929877186060" },
	OrbMesh      = { localUri = "rbxasset://textures/AltarOrb/orb.mesh", published = "rbxassetid://132717489869391" },
	GlowSoft     = { localUri = "rbxasset://textures/AltarOrb/glow_soft.png", published = "rbxassetid://95148021855306" },
	Spark        = { localUri = "rbxasset://textures/AltarOrb/spark_v15.png", published = "rbxassetid://117257921452077" },
	SparkGlint   = { localUri = "rbxasset://textures/AltarOrb/assembly_glint_v19.png", published = "rbxassetid://80920974354606" },
	SparkWisp    = { localUri = "rbxasset://textures/AltarOrb/assembly_wisp_v19.png", published = "rbxassetid://79735940494965" },
	SparkFlecks  = { localUri = "rbxasset://textures/AltarOrb/assembly_flecks_v19.png", published = "rbxassetid://72131715627194" },
	SparkSwirl   = { localUri = "rbxasset://textures/AltarOrb/assembly_swirl_v19.png", published = "rbxassetid://136649526372616" },
	SparkEmber   = { localUri = "rbxasset://textures/AltarOrb/assembly_ember_v19.png", published = "rbxassetid://129832486668143" },
	Charge       = { localUri = "rbxasset://sounds/AltarRecruit/recruit_charge_v22.wav", published = "rbxassetid://110343758658663" },
	Transfer1    = { localUri = "rbxasset://sounds/AltarRecruit/recruit_transfer1_v22.wav", published = "rbxassetid://96214902343908" },
	Transfer2    = { localUri = "rbxasset://sounds/AltarRecruit/recruit_transfer2_v22.wav", published = "rbxassetid://122725546162535" },
	Transfer3    = { localUri = "rbxasset://sounds/AltarRecruit/recruit_transfer3_v22.wav", published = "rbxassetid://124963012959016" },
	Solid1       = { localUri = "rbxasset://sounds/AltarRecruit/recruit_solid1_v22.wav", published = "rbxassetid://101317001630257" },
	Solid2       = { localUri = "rbxasset://sounds/AltarRecruit/recruit_solid2_v22.wav", published = "rbxassetid://118741500790034" },
	Solid3       = { localUri = "rbxasset://sounds/AltarRecruit/recruit_solid3_v22.wav", published = "rbxassetid://80862645408101" },
	Complete     = { localUri = "rbxasset://sounds/AltarRecruit/recruit_complete_v22.wav", published = "rbxassetid://74311072669573" },
}
function C.asset(key)
	local a = C.ASSETS[key]
	if not a then return "" end
	return a.published or a.localUri
end

return C
