-- DiverSystem.server.lua
-- The Aquamen Monolith DIVER. Full loop (per the design):
--   lies by the monolith → BUY → stands up (Revive) → runs to the raft edge → JUMPS into the water →
--   swims out → sinks under → waits DELIVERY_INTERVAL → surfaces WITH A CRATE → swims back → climbs
--   aboard → walks to the monolith → THROWS the crate down beside it → runs off and dives again → ∞.
--   The crate lies welded on the deck until a player CLICKS it (contents + notify), then vanishes.
--
-- GEOMETRY (measured from the real place file with Lune — do not "guess" heights):
--   • Raft_part are MODELS (not parts). The deck surface can only be found by RAYCASTING onto the
--     parts INSIDE those models. Their logs are rotated cylinders, so pos.Y + size.Y/2 is WRONG
--     (gave -377.8 while the true deck is ≈ -380.9 → everything used to float in the sky).
--   • The diver's own authored position in Workspace is ground truth: his hip height above the deck
--     is MEASURED at startup and reused everywhere.
-- All movement is kinematic: the HRP is ANCHORED and driven by CFrame (limbs unanchored + massless
-- so Motor6D animations pose them). Nothing collides → the raft is never disturbed, nothing can be
-- physically flung into the sky.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")

local Config    = require(ReplicatedStorage:WaitForChild("WeaponUpgradeConfig"))
local AssetFind = require(ReplicatedStorage:WaitForChild("AssetFind"))

-- ── config ──
local DIVER_TEMPLATE    = "Diver"
local CRATE_TEMPLATE    = "ResourceCrate"
local DELIVERY_INTERVAL = 60          -- секунд под водой за ходку (боевое значение; было укорочено до 15 для теста)
local WALK_SPEED        = 9           -- calm deck walk
local SWIM_SPEED        = 12          -- must out-swim the raft (SPEED=8) to catch it back, but not zoom
local OFFSHORE_DIST     = 25          -- just off the raft (visible in fog), then he dives
local SWIM_Y_OFFSET     = 0.4         -- body height above the water surface
local SUBMERGE_DEPTH    = 14
local JUMP_DIST         = 9
local JUMP_HEIGHT       = 3.5
local STAND_OFFSET      = 4.5         -- stands this far from the monolith to throw
local THROW_TIME        = 0.8
local FLIGHT_TIME       = 0.5         -- crate arc
local ARC_HEIGHT        = 5
local REVIVE_DELAY      = 2
local MAX_CRATES        = 6
-- loop timings (kept slow/natural on purpose — the diver must never teleport)
local EDGE_OUT          = 9           -- fallback raft-local distance from his spot to the deck edge
local SWIM_OUT_SECONDS  = 3           -- swims on the surface this long before sinking
local SINK_TIME         = 2.6         -- slow descent under water
local SURFACE_TIME      = 1.9         -- slow rise back to the surface
local IDLE_AT_EDGE      = 0.5         -- pauses at the edge before jumping
local CLIMB_TIME        = 1.1         -- slow climb from the water back onto the deck
local LIE_PITCH         = -90         -- lying: whole-body pitch (flip sign if he lies face-down)
local LIE_CLEAR         = 0.95        -- lying body center above the deck
local AQUA              = Color3.fromRGB(60, 210, 235)
-- "Ammo" убран из обычных ящиков: снаряды теперь приносит ФИЗИЧЕСКИЙ ящик с патронами
-- (AmmoCaseSystem) с шансом 25% при доставке — см. deliverCrateAtMonolith.
local CRATE_CONTENTS    = { "Food", "Resources" }
local AMMO_CASE_CHANCE  = 0.25
local CONTENT_COLOR     = { Food = Color3.fromRGB(120, 220, 90), Resources = Color3.fromRGB(230, 180, 70), Ammo = Color3.fromRGB(230, 90, 70) }
local CONTENT_RU        = { Food = "Еда", Resources = "Ресурсы", Ammo = "Снаряды" }
-- crate loot pool: distinct item types a crate can contain (amounts come from the crate's WEIGHT)
local LOOT_POOL = {
	{ name = "Log" },
	{ name = "Stone" },
	{ name = "Leaves" },
}
-- crate SIZE/WEIGHT system: every delivered crate rolls a weight (kg). The weight shows over the
-- crate on hover while it's closed, scales the crate model, and drives the loot:
--   0.2–0.99 кг → 1 item  × 1 unit
--   1.0–1.99 кг → up to 2 items × 2 units each
--   2.0–3.0  кг → up to 3 items × 3 units each (a full 3.0 kg crate always gives all 3)
local CRATE_MIN_KG = 0.2
local CRATE_MAX_KG = 3.0
-- GOLDEN (legendary) crate: rolled on delivery. Looks golden, loot units are ×3 the base tier
-- (3/6/9 per item) and PIRATE COINS burst out with the mob-death coin physics (pop up, scatter,
-- ricochet, comet-trail magnet to the player — reuses _G.SpawnPirateCoins from ShipCombat):
--   coins = 3 × tier → 0.2кг = 3, 1–2кг = 6, 2–3кг = 9, a full 3.0кг crate = 12
-- TREASURE (special crate) roll — driven by the monolith's "Шанс сокровищ" upgrade
-- (_G.GetMonolithUpgrades from DiverShop): base 5% +2.5%/lvl, cap 15%. When a treasure procs,
-- it's GOLDEN 80% / DIAMOND 20%. The crate weight range also comes from the upgrades
-- ("Размер коробок": +0.2 min / +0.2 max per level over the 0.2–3.0 base).
local BASE_TREASURE_CHANCE = 0.05
local DIAMOND_SHARE        = 0.2
local GOLD_LOOT_MULT    = 3
local GOLD_COIN_POP     = 0.45 -- coin burst velocity multiplier (1 = ship-kill default; lower = tighter)
local GOLD_COIN_SIZE    = 0.7  -- coin icon scale (1 = ship-kill default)
local DIAMOND_IRON_CHANCE  = 0.5 -- rare loot (iron ingots ×2–6) chance inside a diamond crate
local DIAMOND_COLOR        = Color3.fromRGB(118, 214, 255)
local DIAMOND_LID_COLOR    = Color3.fromRGB(202, 244, 255)

--[[ ДАЙВЕР (3 ур.): если на плоту есть игрок с активным дайвером 3 уровня,
     шанс редких сокровищ удваивается.
     ⚠️ Бонус берём «хотя бы у одного», и это ОСТАЁТСЯ верным даже теперь, когда
     лут достаётся только открывшему: шанс решается в момент ПОЯВЛЕНИЯ ящика, а
     кто его потом откроет, ещё неизвестно. Класс дайвера здесь работает на всю
     команду — он улучшает саму добычу, а не чей-то личный карман. ]]
local function anyDiverLevel3()
	for _, plr in ipairs(Players:GetPlayers()) do
		if Config.activeClassLevel(plr, "diver") >= 3 then
			return true
		end
	end
	return false
end

-- live upgrade effects (safe defaults before DiverShop loads)
local function monolithUpgrades()
	local upg = _G.GetMonolithUpgrades and _G.GetMonolithUpgrades() or nil
	local treasure = (upg and upg.treasureChance) or BASE_TREASURE_CHANCE
	if anyDiverLevel3() then
		treasure = math.min(1, treasure * 2)
	end
	return {
		treasureChance = treasure,
		crateMin = (upg and upg.crateMin) or CRATE_MIN_KG,
		crateMax = (upg and upg.crateMax) or CRATE_MAX_KG,
	}
end

-- one full crate roll: weight from the upgraded range + the treasure tier
local function rollCrateStats()
	local upg = monolithUpgrades()
	local weight = math.random(math.floor(upg.crateMin * 10), math.floor(upg.crateMax * 10)) / 10
	local golden, diamond = false, false
	if math.random() < upg.treasureChance then
		if math.random() < DIAMOND_SHARE then diamond = true else golden = true end
	end
	return weight, golden, diamond
end
local GOLD_COLOR        = Color3.fromRGB(212, 160, 44)
local GOLD_LID_COLOR    = Color3.fromRGB(255, 224, 108)

local crateCount    = 0
local diverWorking  = false
local nextDeliveryAt = 0
local skipRequested = false
-- GROUND TRUTH captured from the authored starter placement (raft-local): where he stands by the
-- monolith and where crates go. No deck raycasts in the loop — these two points cannot lie.
local G_standLocal  = nil   -- CFrame (raft-local) of his authored stand spot
local G_crateLocal  = nil   -- Vector3 (raft-local) where delivered crates sit

-- ── remotes / notify ──
local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = ReplicatedStorage end
	return r
end
local diverNotify = ensureRemote("DiverNotify")

-- roll the crate's contents from its WEIGHT (see the tier table above). Distinct items, shuffled →
-- any combination can come up. Swap for the real prize-table roll later; the FX adapts to any count.
local function rollLoot(weightKg)
	local w = math.max(tonumber(weightKg) or 1, CRATE_MIN_KG) -- upgraded crates can exceed the base max
	-- tier keeps growing past 3 with upgraded crate sizes: <1кг→1, 1..2→2, 2..3→3, 3..4→4, …
	local tier = math.max(1, math.floor(w + 1))
	local count = (w >= CRATE_MAX_KG - 0.05) and 3 or math.random(1, tier)
	local order = {}
	for i = 1, #LOOT_POOL do order[i] = i end
	for i = #order, 2, -1 do
		local j = math.random(i)
		order[i], order[j] = order[j], order[i]
	end
	local drops = {}
	for i = 1, math.min(count, #LOOT_POOL) do
		table.insert(drops, { name = LOOT_POOL[order[i]].name, amount = tier })
	end
	return drops
end

--[[ ⚠️ ЛУТ ПОЛУЧАЕТ ТОТ, КТО ОТКРЫЛ ЯЩИК, А НЕ ВСЕ НА СЕРВЕРЕ.
     Здесь шёл цикл по Players:GetPlayers(), то есть каждый ящик выдавал полный
     набор ресурсов КАЖДОМУ игроку. В одиночку это незаметно, а в компании
     превращалось в умножение добычи на число игроков: открыл один — получили
     все, и открывать по очереди становилось выгоднее, чем нырять.
     Монеты из того же ящика с самого начала летели именно открывшему
     (SpawnPirateCoins получает plr) — теперь и ресурсы ведут себя так же. ]]
local function grantLoot(player, drops)
	if not (player and player.Parent) then return end
	for _, d in ipairs(drops) do
		-- no "Дайвер принёс" toast — the inventory pickup popups + the flying icons say it all
		if _G.AddResourceToInventory then pcall(_G.AddResourceToInventory, player, d.name, d.amount) end
	end
end

-- ── raft geometry (the REAL deck) ──
-- There can be MORE THAN ONE model named "Raft" in Workspace (lobby/template copies). The player's
-- raft is the one the monolith stands on → pick the "Raft" whose PrimaryPart is nearest the monolith.
local raftCache, raftCacheAt = nil, -math.huge
local function raft()
	if raftCache and raftCache.Parent and os.clock() - raftCacheAt < 5 then return raftCache end
	local monoPos
	local m = _G.GetMonolith and _G.GetMonolith()
	if m then local ok, piv = pcall(function() return m:GetPivot().Position end); if ok then monoPos = piv end end
	local best, bestD
	for _, c in ipairs(workspace:GetChildren()) do
		if c:IsA("Model") and c.Name == "Raft" and c.PrimaryPart and c:FindFirstChild("Raft_part") then
			local d = monoPos and (c.PrimaryPart.Position - monoPos).Magnitude or 0
			if not best or d < bestD then best, bestD = c, d end
		end
	end
	raftCache, raftCacheAt = best, os.clock()
	return best
end
local function rpp() local r = raft(); return r and r.PrimaryPart end

-- the REAL deck logs only: solid (CanCollide) and visible. Build-preview GHOST sections are also
-- named Raft_part but are transparent/non-solid — walking on those was "walking on air".
local deckPartsCache, deckPartsAt = {}, -math.huge
local function deckParts()
	if os.clock() - deckPartsAt > 2 then
		deckPartsCache = {}
		local r = raft()
		if r then
			local ppY = r.PrimaryPart and r.PrimaryPart.Position.Y or nil
			local function take(p)
				if p:IsA("BasePart") and p.CanCollide and p.Transparency < 0.5
					and (not ppY or math.abs(p.Position.Y - ppY) < 6) then -- deck-level ONLY: sunken/stray logs are not floor
					table.insert(deckPartsCache, p)
				end
			end
			for _, c in ipairs(r:GetChildren()) do
				if c.Name == "Raft_part" then
					if c:IsA("BasePart") then take(c)
					else for _, p in ipairs(c:GetDescendants()) do take(p) end end
				end
			end
		end
		deckPartsAt = os.clock()
	end
	return deckPartsCache
end

-- the TRUE deck-surface world Y at (x, z): ray down ONTO the deck logs only.
-- strict=true → nil when there is NO log under that spot (footing check); otherwise falls back to
-- the last seen deck height (Y smoothing only, never direction).
local lastDeckY = nil
local function deckYAt(x, z, strict)
	local list = deckParts()
	local base = rpp()
	if #list == 0 or not base then return strict and nil or lastDeckY end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = list
	local origin = Vector3.new(x, base.Position.Y + 40, z)
	local res = workspace:Raycast(origin, Vector3.new(0, -120, 0), params)
	-- accept ONLY hits at true deck level (just above the waterline the raft floats at) — a hit on a
	-- sunken or misplaced log is NOT walkable floor
	if res and res.Position.Y > base.Position.Y - 1.5 and res.Position.Y < base.Position.Y + 6 then
		lastDeckY = res.Position.Y
		return res.Position.Y
	end
	return strict and nil or lastDeckY
end

-- first point WITH actual deck footing probing from (x,z) along dirXZ (used to climb onto real logs)
local function findFoothold(x, z, dirXZ)
	for dist = 2, 18, 2 do
		local px, pz = x + dirXZ.X * dist, z + dirXZ.Z * dist
		local dy = deckYAt(px, pz, true)
		if dy then return Vector3.new(px, dy, pz) end
	end
	return nil
end

local function raftRadius()
	if _G.GetRaftRadius then local rr = _G.GetRaftRadius(); if rr then return rr end end
	local r = raft()
	if not r then return 14 end
	local _, size = r:GetBoundingBox()
	return math.max(size.X, size.Z) * 0.5
end

-- radius of the actual DECK (from the real log parts — the bounding box includes the mast/board
-- and overshoots, which made him "board" in open water)
local function deckRadius()
	local base = rpp()
	if not base then return raftRadius() end
	local best = 6
	for _, p in ipairs(deckParts()) do
		local d = (Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(base.Position.X, 0, base.Position.Z)).Magnitude
		if d + 2 > best then best = d + 2 end
	end
	return best
end

-- the water surface near (x, z) (terrain water ray; falls back to just under the deck)
local function waterYAt(x, z, ignore)
	local base = rpp()
	local refY = base and base.Position.Y or 0
	local params = RaycastParams.new()
	params.IgnoreWater = false
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local res = workspace:Raycast(Vector3.new(x, refY + 60, z), Vector3.new(0, -300, 0), params)
	if res and res.Material == Enum.Material.Water then return res.Position.Y end
	return refY -- the raft floats AT the water line (BoatMovement holds it there)
end

local function monolithPivot()
	local m = _G.GetMonolith and _G.GetMonolith()
	return m and m:GetPivot().Position or nil
end

--[[ ⚠️ ТОЧКИ ВОДОЛАЗА — ОТ МОНОЛИТА, А НЕ ОТ ПЛОТА.
     Место стояния и место ящиков снимались один раз в осях PrimaryPart плота.
     Игрок перенёс тотем — а водолаз шёл складывать ящики на старое место.
     Теперь те же точки хранятся в осях монолита и пересчитываются на каждом
     обращении: тотем уехал — точки уехали с ним. Кадр монолита берём по
     детали, а не по пивоту (пивот модели без PrimaryPart не едет за плотом). ]]
local MonoRel = {}   -- stand: CFrame, crate: Vector3 — в осях монолита
local function monolithFrame()
	local m = _G.GetMonolith and _G.GetMonolith()
	-- до регистрации в MonolithRepair модель уже стоит в плоту: берём её напрямую,
	-- чтобы снимок точек был от ИСХОДНОГО места тотема, а не от перенесённого
	if not m then
		local r = raft()
		m = r and r:FindFirstChild("Monolit_Aquamen", true)
	end
	if not m then return nil end
	local part = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	return part and part.CFrame or nil
end
--[[ ⚠️ СНИМАЕМ ЛЕНИВО. При старте водолаза монолит ещё не зарегистрирован
     (MonolithRepair «waiting for Monolit_Aquamen»), и снимок в осях монолита
     оставался пустым — работал запасной путь от плота, водолаз носил ящики
     на старое место. Теперь при первом появлении монолита переводим
     авторские точки (в осях плота) в его оси один раз и дальше идём от него. ]]
local function captureMonoRel()
	local b, mf = rpp(), monolithFrame()
	if not (b and mf) then return false end
	if not MonoRel.stand and G_standLocal then MonoRel.stand = mf:ToObjectSpace(b.CFrame * G_standLocal) end
	if not MonoRel.crate and G_crateLocal then MonoRel.crate = mf:PointToObjectSpace(b.CFrame:PointToWorldSpace(G_crateLocal)) end
	return MonoRel.stand ~= nil
end
local function standLocalNow()
	local b, mf = rpp(), monolithFrame()
	if b and mf and not MonoRel.stand then captureMonoRel() end
	if b and mf and MonoRel.stand then return b.CFrame:ToObjectSpace(mf * MonoRel.stand) end
	return G_standLocal
end
local function crateLocalNow()
	local b, mf = rpp(), monolithFrame()
	if b and mf and not MonoRel.crate then captureMonoRel() end
	if b and mf and MonoRel.crate then return b.CFrame:PointToObjectSpace(mf:PointToWorldSpace(MonoRel.crate)) end
	return G_crateLocal
end
-- тотем стоит на плоту? Унесён в инвентарь (RaftRelocate) или отсутствует — рейсов нет
local function monolithOnRaft()
	local m = _G.GetMonolith and _G.GetMonolith()
	local r = raft()
	return m ~= nil and r ~= nil and m.Parent == r
end

-- deck surface Y at (x,z) using the WHOLE raft model — so player-BUILT floor tiles count, not just the
-- original "Raft_part" logs (that was why he walked past the edge on a default raft and stopped at the
-- OLD edge on a built one). Ray straight down; accept only a hit near the reference deck height refY
-- (walls / mast / monolith stick up and are correctly rejected → he stops before them). nil = off the deck.
local function deckHitY(x, z, refY, band)
	local r = raft()
	if not r then return nil end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { r }
	local res = workspace:Raycast(Vector3.new(x, refY + 20, z), Vector3.new(0, -40, 0), params)
	if res and math.abs(res.Position.Y - refY) <= (band or 3) then return res.Position.Y end
	return nil
end

-- ── rig helpers ──
local function findRig(model)
	if model:FindFirstChild("Torso") or model:FindFirstChild("Head") then return model end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Model") and (d:FindFirstChild("Torso") or d:FindFirstChild("Head")) then return d end
	end
	return model
end

local function ensureHumanoid(model)
	local hum = model:FindFirstChildWhichIsA("Humanoid", true)
	local rig = findRig(model)
	if not hum then
		local torso = rig:FindFirstChild("Torso") or rig:FindFirstChildWhichIsA("BasePart")
		if not torso then return nil, nil end
		hum = Instance.new("Humanoid"); hum.Parent = rig
	end
	hum.BreakJointsOnDeath = false
	local hrp = rig:FindFirstChild("HumanoidRootPart") or hum.RootPart
	return hum, hrp
end

local function loadTracks(hum, model)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	for _, t in ipairs(animator:GetPlayingAnimationTracks()) do t:Stop(0) end
	local KEYS = {
		swim = { "swim", "dive" }, walk = { "walk", "run", "stride" }, jump = { "jump", "leap" },
		revive = { "revive", "getup", "get_up", "wake", "rise", "stand" }, throw = { "throw", "toss" },
	}
	local looped = { swim = true, walk = true }
	local tracks = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Animation") and d.AnimationId ~= "" then
			local ln = d.Name:lower()
			if not ln:find("before") then -- "Before_live" is the lie, never a movement track
				for key, pats in pairs(KEYS) do
					if not tracks[key] then
						for _, p in ipairs(pats) do
							if ln:find(p) then
								local ok, tr = pcall(function() return animator:LoadAnimation(d) end)
								if ok and tr then
									tr.Priority = Enum.AnimationPriority.Action
									tr.Looped = looped[key] == true
									tracks[key] = tr
								end
								break
							end
						end
					end
				end
			end
		end
	end
	local summary = {}
	for _, k in ipairs({ "walk", "jump", "swim", "revive", "throw" }) do
		summary[#summary + 1] = k .. "=" .. (tracks[k] and "OK" or "MISSING")
	end
	print("[DiverSystem] movement tracks: " .. table.concat(summary, "  "))
	return tracks
end

-- PERMANENT raft weld. The diver's root is welded to the raft ONCE and NEVER unwelded — all movement
-- (walk, jump, swim, dive, stand, lie) is done by changing this legacy Weld's C0 offset. Why: welding or
-- UNwelding a body into the raft's physics assembly forces a network-ownership recompute, and the raft
-- visibly DESPAWNS for a frame (dumping the standing player into the sea). A permanent weld changes the
-- joint TRANSFORM only (never the assembly topology) → no recompute, no despawn, AND it's rigid so he
-- rides the raft with zero client jitter. The diver is massless + non-colliding → no effect on buoyancy.
local function ensureRaftWeld(hrp)
	local w = hrp:FindFirstChild("_DiverRaftWeld")
	if w and w:IsA("Weld") and w.Part0 and w.Part0.Parent then return w end
	if w then w:Destroy() end
	local base = rpp()
	if not base then return nil end
	hrp.Anchored = false
	w = Instance.new("Weld")
	w.Name = "_DiverRaftWeld"
	w.Part0 = base
	w.Part1 = hrp
	w.C1 = CFrame.new()
	w.C0 = base.CFrame:Inverse() * hrp.CFrame -- hold his current world pose
	w.Parent = hrp
	pcall(function() base:SetNetworkOwner(nil) end) -- keep the whole assembly server-owned
	return w
end

-- position the diver's root at world CFrame `cf` via the permanent weld's C0 (rigid, rides the raft)
local function driveTo(hrp, cf)
	local w = ensureRaftWeld(hrp)
	if w and w.Part0 then
		w.C0 = w.Part0.CFrame:Inverse() * cf
	else
		hrp.Anchored = true; hrp.CFrame = cf
	end
end

-- "step": place the root at pos, facing dir (kept flat/upright) — the common movement primitive
local function place(hrp, pos, dir)
	local target
	if dir and Vector3.new(dir.X, 0, dir.Z).Magnitude > 0.01 then
		target = CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z).Unit)
	else
		target = CFrame.new(pos) * hrp.CFrame.Rotation
	end
	driveTo(hrp, target)
end

-- place at a FULL CFrame (preserves pitch — used for the lying pose and the exact authored stance)
local function weldDiverAt(hrp, cf) driveTo(hrp, cf) end
-- (kept for call sites) the weld is permanent now, so this just makes sure it exists — never unwelds
local function clearDiverWeld(hrp) ensureRaftWeld(hrp) end

-- ── shared phase helpers (defined up here so throwCrate + gatherTrip can both use them) ──
local function playT(track, f) if track then pcall(function() track:Play(f or 0.2) end) end end
local function stopT(track, f) if track then pcall(function() track:Stop(f or 0.2) end) end end
local function alive(state) return state.diver.Parent and not state.dead and not state.abort end

-- No-ops now: the permanent weld already rides the raft rigidly, so nothing needs to apply the raft's
-- per-frame motion delta (that hand-rolled "carry" was only for the old anchored-kinematic mode).
local function carryByRaft(state) end
local function resetCarry(state) end

local function setupDiver(diver)
	local hum, hrp = ensureHumanoid(diver)
	if not hum or not hrp then return nil end
	hrp = hum.RootPart or hrp
	for _, d in ipairs(diver:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Massless = true
			-- NO water forces: he is WELDED to the raft, and a massless body underwater gets a large
			-- net BUOYANT force (∝ volume, not mass) applied 14 studs below / beside the raft — a
			-- lever that torqued the raft up to a 42° capsize every dive (caught by RaftTiltProbe).
			pcall(function() d.EnableFluidForces = false end)
			d.Anchored = (d == hrp) -- ONLY the root is anchored (kinematic); limbs follow Motor6D
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d.Disabled = true
		end
	end
	pcall(function() diver.PrimaryPart = hrp end)
	hum.EvaluateStateMachine = false
	hum.AutoRotate = false
	hum.PlatformStand = true -- never apply balance/standing forces (we drive him ourselves)
	-- he lives in the sea and under the raft: nothing may hurt or delete him
	diver:SetAttribute("WaterImmune", true)   -- toxic-water systems skip him (same as SwimmingPirate)
	diver:SetAttribute("RaftFriendly", true)  -- RaftUnderGuard never ejects him
	hum.MaxHealth = 1e9
	hum.Health = 1e9
	local tracks = loadTracks(hum, diver)
	return hum, hrp, tracks
end

-- ── FX ──
local function burstAt(pos, big)
	local a = Instance.new("Part")
	a.Anchored = true; a.CanCollide = false; a.CanQuery = false; a.Transparency = 1
	a.Size = Vector3.new(1, 1, 1); a.CFrame = CFrame.new(pos); a.Parent = workspace
	local att = Instance.new("Attachment"); att.Parent = a
	local sp = Instance.new("ParticleEmitter")
	sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sp.Color = ColorSequence.new(AQUA, Color3.fromRGB(255, 255, 255)); sp.LightEmission = 0.8
	sp.Size = NumberSequence.new(big and 1.3 or 0.9, 0.1); sp.Lifetime = NumberRange.new(0.4, 0.9)
	sp.Speed = NumberRange.new(big and 25 or 12, big and 40 or 20); sp.SpreadAngle = Vector2.new(180, 180)
	-- server-side :Emit() does NOT replicate to clients — burst via a short enabled Rate window
	sp.Rate = big and 220 or 100; sp.Parent = att
	task.delay(0.25, function() sp.Enabled = false end)
	Debris:AddItem(a, 1.2)
end

local function splashAt(pos)
	local a = Instance.new("Part")
	a.Anchored = true; a.CanCollide = false; a.CanQuery = false; a.Transparency = 1
	a.Size = Vector3.new(1, 1, 1); a.CFrame = CFrame.new(pos); a.Parent = workspace
	local att = Instance.new("Attachment"); att.Parent = a
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(185, 222, 240)); e.LightEmission = 0.3
	e.Size = NumberSequence.new(2, 4.5)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.3, 0.6); e.Speed = NumberRange.new(8, 14)
	e.SpreadAngle = Vector2.new(60, 60); e.Acceleration = Vector3.new(0, -10, 0)
	-- server-side :Emit() does NOT replicate to clients — burst via a short enabled Rate window
	e.Rate = 80; e.Parent = att
	task.delay(0.2, function() e.Enabled = false end)
	Debris:AddItem(a, 1)
end

-- ── crates ──
-- forcedContent: keep the SAME content (lid color + label) as the crate the diver carried — the
-- delivered crate is a fresh instance, and re-rolling made him "нести один ящик, а ставить другой"
local function buildCrate(forcedContent)
	local tmpl = AssetFind.find(CRATE_TEMPLATE)
	local crate
	if tmpl and (tmpl:IsA("Model") or tmpl:IsA("BasePart")) then
		crate = tmpl:Clone()
		if crate:IsA("BasePart") then
			local m = Instance.new("Model"); crate.Parent = m; m.PrimaryPart = crate; crate = m
		elseif not crate.PrimaryPart then
			crate.PrimaryPart = crate:FindFirstChildWhichIsA("BasePart")
		end
	else
		crate = Instance.new("Model"); crate.Name = "ResourceCrate"
		local box = Instance.new("Part")
		box.Name = "Crate"; box.Size = Vector3.new(2.2, 2.0, 2.2)
		box.Color = Color3.fromRGB(120, 82, 44); box.Material = Enum.Material.WoodPlanks; box.Parent = crate
		crate.PrimaryPart = box
		local lid = Instance.new("Part")
		lid.Name = "Lid"; lid.Size = Vector3.new(2.35, 0.35, 2.35)
		lid.Color = AQUA; lid.Material = Enum.Material.Neon
		lid.CFrame = box.CFrame * CFrame.new(0, 1.1, 0); lid.Parent = crate
		local w = Instance.new("WeldConstraint"); w.Part0 = box; w.Part1 = lid; w.Parent = box
	end
	for _, p in ipairs(crate:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false; p.CanCollide = false; p.Massless = true; p.CanQuery = false
			-- crates ride welded to the diver/raft — water buoyancy on them would torque the raft too
			pcall(function() p.EnableFluidForces = false end)
		end
	end
	local content = forcedContent or CRATE_CONTENTS[math.random(#CRATE_CONTENTS)]
	crate:SetAttribute("Content", content)
	local lidP = crate:FindFirstChild("Lid")
	if lidP and lidP:IsA("BasePart") then lidP.Color = CONTENT_COLOR[content] or lidP.Color end
	local mainP = crate.PrimaryPart or crate:FindFirstChildWhichIsA("BasePart")
	if mainP and not mainP:FindFirstChild("CrateLabel") then
		-- HOVER-ONLY tag (enabled by addClickOpen's MouseHoverEnter while the crate is closed):
		-- content name on top, the crate's WEIGHT below it
		local bb = Instance.new("BillboardGui")
		bb.Name = "CrateLabel"; bb.Size = UDim2.fromOffset(130, 46); bb.StudsOffset = Vector3.new(0, 2.4, 0)
		bb.AlwaysOnTop = true; bb.Adornee = mainP; bb.Enabled = false; bb.Parent = mainP
		local lbl = Instance.new("TextLabel")
		lbl.Name = "ContentText"
		lbl.Size = UDim2.new(1, 0, 0.55, 0); lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.GothamBlack
		lbl.Text = CONTENT_RU[content] or content; lbl.TextColor3 = CONTENT_COLOR[content] or Color3.new(1, 1, 1)
		lbl.TextStrokeTransparency = 0.3; lbl.TextScaled = true; lbl.Parent = bb
		local wl = Instance.new("TextLabel")
		wl.Name = "WeightText"
		wl.Position = UDim2.fromScale(0, 0.55); wl.Size = UDim2.new(1, 0, 0.45, 0)
		wl.BackgroundTransparency = 1; wl.Font = Enum.Font.GothamBold
		wl.Text = ""; wl.TextColor3 = Color3.fromRGB(255, 255, 255)
		wl.TextStrokeTransparency = 0.3; wl.TextScaled = true; wl.Parent = bb
	end
	return crate
end

local function fadeAndRemove(model, dur)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then TweenService:Create(p, TweenInfo.new(dur), { Transparency = 1 }):Play() end
	end
	Debris:AddItem(model, dur + 0.15)
end

-- ── crate FX (all replicated-safe: tweens + Rate-window emitters, never server :Emit) ──

-- THUD-in: dust shockwave ring on the deck + wood chips + a brown dust puff
local function crateDropFX(spot)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(214, 192, 150)
	ring.Anchored = true; ring.CanCollide = false; ring.CanQuery = false; ring.CastShadow = false
	ring.Size = Vector3.new(0.18, 1.4, 1.4)
	ring.CFrame = CFrame.new(spot - Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.25
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.18, 8.5, 8.5), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.6)

	local a = Instance.new("Part")
	a.Anchored = true; a.CanCollide = false; a.CanQuery = false; a.Transparency = 1
	a.Size = Vector3.new(1, 1, 1); a.CFrame = CFrame.new(spot); a.Parent = workspace
	local att = Instance.new("Attachment"); att.Parent = a
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(178, 156, 120), Color3.fromRGB(210, 196, 168))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.0), NumberSequenceKeypoint.new(1, 2.6) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.35, 0.6)
	dust.Speed = NumberRange.new(4, 8)
	dust.SpreadAngle = Vector2.new(80, 80)
	dust.Acceleration = Vector3.new(0, -6, 0)
	dust.Rate = 80; dust.Parent = att
	local chips = Instance.new("ParticleEmitter")
	chips.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	chips.Color = ColorSequence.new(Color3.fromRGB(150, 108, 62))
	chips.Size = NumberSequence.new(0.3, 0.08)
	chips.Lifetime = NumberRange.new(0.3, 0.55)
	chips.Speed = NumberRange.new(10, 16)
	chips.SpreadAngle = Vector2.new(70, 70)
	chips.Acceleration = Vector3.new(0, -70, 0)
	chips.Rate = 90; chips.Parent = att
	task.delay(0.18, function() dust.Enabled = false; chips.Enabled = false end)
	Debris:AddItem(a, 1)
end

-- pop-in: the crate lands squashed and springs to its final size with a slight overshoot.
-- finalScale comes from the crate's WEIGHT (light crates are visibly small, heavy ones big).
local function cratePopIn(crate, finalScale)
	finalScale = finalScale or 1
	if not crate.PrimaryPart then return end
	task.spawn(function()
		if not pcall(function() crate:ScaleTo(0.55 * finalScale) end) then return end
		local DUR, c1 = 0.32, 1.70158
		local c3 = c1 + 1
		local t0 = os.clock()
		while crate.Parent do
			local x = math.clamp((os.clock() - t0) / DUR, 0, 1)
			local back = 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2 -- back-out easing (overshoot ~1.1)
			pcall(function() crate:ScaleTo((0.55 + 0.45 * back) * finalScale) end)
			if x >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		pcall(function() crate:ScaleTo(finalScale) end)
	end)
end

-- OPEN, v3 (per the design brief):
--   • the lid is KNOCKED OFF sharply — kicked up/aside, gravity-drops onto the deck, lies there, fades
--   • a soft GLOW + light pulse shine out of the open box
--   • the DROPPED ITEM'S ICON flies out spinning → GROWS and stops spinning → hangs still 3s → gone
-- Lid + icon are animated in the crate's LOCAL space / on its attachments → nothing drifts while
-- the raft sails.
local PRIZE_ICONS = { Log = "rbxassetid://116178347748793", Leaves = "rbxassetid://96691360298069",
	Plastic = "rbxassetid://132919988751848", Stone = "rbxassetid://96450657403376",
	Iron_Ingot = "rbxassetid://72890243946368" }

local function crateOpenFX(crate, main, color, drops)
	color = color or AQUA
	local label = main:FindFirstChild("CrateLabel")
	if label then label:Destroy() end -- the prize icon replaces the name tag

	-- 1) LID: a sharp knock-off — kicked up and aside with a fast flip, falls to the deck,
	-- lies there for a beat, fades
	local lid = crate:FindFirstChild("Lid", true)
	if lid and lid:IsA("BasePart") then
		local ghost = lid:Clone()
		for _, c in ipairs(ghost:GetChildren()) do c:Destroy() end
		ghost.Anchored = true; ghost.CanCollide = false; ghost.CanQuery = false
		ghost.Parent = workspace
		local rel = main.CFrame:ToObjectSpace(lid.CFrame)
		lid.Transparency = 1
		-- deck level in crate-local coords: the bottom of the crate body
		local dropY = -(main.Size.Y / 2) - rel.Position.Y + (math.min(lid.Size.X, lid.Size.Y, lid.Size.Z) / 2)
		task.spawn(function()
			local D_KICK, D_FALL, D_REST, D_FADE = 0.13, 0.42, 0.7, 0.3
			local t0 = os.clock()
			while ghost.Parent and main.Parent do
				local t = os.clock() - t0
				local off, spin, tr
				if t < D_KICK then -- the kick: pops up and aside, flipping fast
					local a = t / D_KICK
					off = Vector3.new(0.55 * a, 0.95 * a, -0.2 * a)
					spin = math.rad(150 * a)
					tr = 0
				elseif t < D_KICK + D_FALL then -- gravity fall down to the deck, still flipping
					local a = (t - D_KICK) / D_FALL
					off = Vector3.new(0.55 + 1.5 * a, 0.95 + (dropY - 0.95) * a * a, -0.2 - 0.5 * a)
					spin = math.rad(150 + 210 * a)
					tr = 0
				else -- lies on the deck, then fades
					off = Vector3.new(2.05, dropY, -0.7)
					spin = math.rad(360)
					tr = math.clamp((t - D_KICK - D_FALL - D_REST) / D_FADE, 0, 1)
				end
				ghost.CFrame = main.CFrame * rel * CFrame.new(off) * CFrame.Angles(spin, math.rad(25), 0)
				ghost.Transparency = tr
				if t >= D_KICK + D_FALL + D_REST + D_FADE then break end
				RunService.Heartbeat:Wait()
			end
			ghost:Destroy()
		end)
	end

	-- 2) GLOW out of the open box + a light pulse
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, main.Size.Y / 2 + 0.15, 0)
	top.Parent = main

	local glow = Instance.new("ParticleEmitter") -- soft glow puffs drifting up
	glow.Texture = "rbxasset://textures/particles/smoke_main.dds"
	glow.Color = ColorSequence.new(color)
	glow.LightEmission = 1
	glow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 2.3) })
	glow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	glow.Lifetime = NumberRange.new(0.6, 0.9)
	glow.Speed = NumberRange.new(2, 4)
	glow.SpreadAngle = Vector2.new(12, 12)
	glow.EmissionDirection = Enum.NormalId.Top
	glow.Rate = 18; glow.Enabled = false
	glow.Parent = top

	local light = Instance.new("PointLight")
	light.Color = color; light.Range = 11; light.Brightness = 0
	light.Parent = main

	task.delay(0.15, function() -- the lid has been knocked clear → the prize shines out
		glow.Enabled = true
		light.Brightness = 4
		TweenService:Create(light, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 0 }):Play()
	end)
	task.delay(1.8, function() glow.Enabled = false end)

	-- 3) PRIZE ICONS: each rolled item flies out of the box spinning, the group FANS OUT sideways
	-- (1 → center, 2 → pair, 3 → trio), launches are staggered like a burst, then every icon grows,
	-- stops spinning upright, hangs a beat and evaporates together with the crate.
	-- BillboardGuis adorned to the crate's attachment, so everything rides the sailing raft.
	drops = drops or { LOOT_POOL[1] }
	local n = math.min(#drops, 4)
	local FAN = ({ { 0 }, { -1.5, 1.5 }, { -2.4, 0, 2.4 }, { -3.4, -1.15, 1.15, 3.4 } })[n]
	local BIG = (n == 1 and 3.0) or (n == 4 and 2.0) or 2.3 -- final icon size (studs)
	local START = (n == 1) and 1.5 or 1.2                   -- launch size
	for i = 1, n do
		local drop = drops[i]
		local bb = Instance.new("BillboardGui")
		bb.Name = "PrizeIcon" .. i
		bb.Adornee = top; bb.AlwaysOnTop = true; bb.LightInfluence = 0
		bb.Size = UDim2.new(START, 0, START, 0) -- BillboardGui scale units = studs
		bb.StudsOffset = Vector3.new(0, 0.3, 0)
		bb.Enabled = false -- hidden until its staggered launch
		bb.Parent = main
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = PRIZE_ICONS[drop.name] or PRIZE_ICONS.Log
		img.Parent = bb
		local fanX = FAN[i]
		task.spawn(function()
			if not bb.Parent then return end
			bb.Enabled = true -- all icons burst out of the box SIMULTANEOUSLY, fanning apart mid-air
			local D_RISE, D_GROW, D_HOLD, D_FADE = 0.5, 0.35, 0.55, 0.35
			local riseY = 2.8 + (i - 1) * 0.2 -- slight height variety so the trio doesn't look stamped
			local SPIN = 540 -- deg/s while flying out
			local rot, growStartRot = 0, nil
			local t0 = os.clock()
			while bb.Parent do
				local dt = RunService.Heartbeat:Wait()
				local t = os.clock() - t0
				if t < D_RISE then -- shoots up out of the box, spinning, drifting to its fan slot
					local a = 1 - (1 - t / D_RISE) ^ 2
					bb.StudsOffset = Vector3.new(fanX * a, 0.3 + riseY * a, 0)
					rot = rot + SPIN * dt
					img.Rotation = rot % 360
				elseif t < D_RISE + D_GROW then -- grows bigger while the spin winds down to upright
					local a = (t - D_RISE) / D_GROW
					if not growStartRot then
						growStartRot = img.Rotation % 360
						if growStartRot > 180 then growStartRot = growStartRot - 360 end -- shortest path to 0
					end
					local e = 1 - (1 - a) ^ 3
					local s = START + (BIG - START) * e
					bb.Size = UDim2.new(s, 0, s, 0)
					img.Rotation = growStartRot * (1 - e)
				elseif t < D_RISE + D_GROW + D_HOLD then -- hangs still, upright
					img.Rotation = 0
				else -- fades away
					local a = math.clamp((t - D_RISE - D_GROW - D_HOLD) / D_FADE, 0, 1)
					img.ImageTransparency = a
					if a >= 1 then break end
				end
			end
			bb:Destroy()
		end)
	end

	-- 4) the opened crate dissolves once the lid has landed — in step with the icon's fade
	task.delay(1.4, function()
		if not crate.Parent then return end
		for _, p in ipairs(crate:GetDescendants()) do
			if p:IsA("BasePart") then TweenService:Create(p, TweenInfo.new(0.4), { Transparency = 1 }):Play() end
		end
	end)
	Debris:AddItem(crate, 2.8) -- covers the last staggered icon's full flight
end

local function addClickOpen(crate, main)
	local cd = Instance.new("ClickDetector")
	cd.MaxActivationDistance = 24
	cd.Parent = main
	-- the weight tag shows only while HOVERING a CLOSED crate
	cd.MouseHoverEnter:Connect(function()
		if crate:GetAttribute("_Taken") then return end
		local label = main:FindFirstChild("CrateLabel")
		if label then label.Enabled = true end
	end)
	cd.MouseHoverLeave:Connect(function()
		local label = main:FindFirstChild("CrateLabel")
		if label then label.Enabled = false end
	end)
	cd.MouseClick:Connect(function(plr)
		if crate:GetAttribute("_Taken") then return end
		crate:SetAttribute("_Taken", true)
		crateCount = math.max(0, crateCount - 1)
		cd:Destroy() -- no longer clickable while the open sequence plays
		local golden = crate:GetAttribute("Golden") == true
		local diamond = crate:GetAttribute("Diamond") == true
		local drops = rollLoot(crate:GetAttribute("WeightKg")) -- weight → item count + units each
		local fxColor = CONTENT_COLOR[crate:GetAttribute("Content")]
		local coins = 0
		local crateMax = monolithUpgrades().crateMax -- "full crate" bonus tracks the upgraded range
		local w = math.clamp(tonumber(crate:GetAttribute("WeightKg")) or 1, CRATE_MIN_KG, crateMax)
		local tier = math.max(1, math.floor(w + 1)) -- keeps growing past 3 with upgraded crates
		if diamond then
			-- RARE loot on top of the normal items: iron ingots 2–6 with a 50% chance per crate
			if math.random() < DIAMOND_IRON_CHANCE then
				table.insert(drops, 1, { name = "Iron_Ingot", amount = math.random(2, 6) })
			end
			fxColor = DIAMOND_LID_COLOR
			coins = tier * 20 -- 20 / 40 / 60 by weight
		elseif golden then
			for _, d in ipairs(drops) do d.amount = d.amount * GOLD_LOOT_MULT end -- ×3 units per item
			fxColor = GOLD_LID_COLOR
			coins = tier * 3
			if w >= crateMax - 0.05 then coins = math.max(coins, 12) end -- full-crate guarantee
		end
		-- PIRATE COINS burst out with the mob-death physics: pop up, scatter, ricochet, then
		-- comet-trail home to the opener (ShipCombat's system), riding the sailing raft
		if coins > 0 and _G.SpawnPirateCoins then
			task.delay(0.25, function() -- let the lid fly off first
				_G.SpawnPirateCoins(main.Position + Vector3.new(0, 1.2, 0), plr, coins, nil,
					{ pop = GOLD_COIN_POP, size = GOLD_COIN_SIZE, follow = rpp() })
			end)
		end
		crateOpenFX(crate, main, fxColor, drops)
		grantLoot(plr, drops)
		if _G.OnCrateCollected then pcall(_G.OnCrateCollected, plr, crate) end
	end)
end

-- park the crate on the deck: WELDED to the raft (massless + non-colliding). It rides the raft rigidly
-- in the same physics step → no jitter, and being massless it can't disturb the raft's buoyancy.
-- Click to open.
local function parkCrate(crate, main, pos)
	local base = rpp()
	for _, p in ipairs(crate:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = false; p.CanCollide = false; p.Massless = true; p.CanQuery = true end
	end
	crate:PivotTo(CFrame.new(pos))
	if base then
		for _, p in ipairs(crate:GetDescendants()) do if p:IsA("BasePart") then pcall(function() p.CollisionGroup = "Raft" end) end end
		-- Pin the crate to the SERVER *before* welding it into the raft assembly. If a free part still owned
		-- by a nearby player is welded in, Roblox reassigns the merged assembly's ownership — and that
		-- transition is what makes the raft blink/despawn for a frame. Both sides server-owned → no
		-- reassignment → no flicker. (Same reason the diver uses a permanent weld.)
		pcall(function() main:SetNetworkOwner(nil) end)
		local w = Instance.new("WeldConstraint"); w.Part0 = main; w.Part1 = base; w.Parent = main
		pcall(function() base:SetNetworkOwner(nil) end)
	else
		for _, p in ipairs(crate:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true end end
	end
	addClickOpen(crate, main)
	crateCount = crateCount + 1
end

-- ── carry / throw ──
local function handPart(rig)
	return rig:FindFirstChild("Right Arm", true) or rig:FindFirstChild("RightHand", true)
		or rig:FindFirstChild("RightLowerArm", true)
end
local function armJoint(rig)
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("Motor6D") then
			local n = d.Name:lower()
			if n == "right shoulder" or n == "rightshoulder" then return d, d.C0 end
		end
	end
	return nil, nil
end

-- ── crate stats (weight + golden), rolled ONCE when the diver SURFACES with the crate, so the
-- one in his hands already looks exactly like the one he'll deliver ──
local function crateScaleFor(weight)
	return 0.8 + (weight - CRATE_MIN_KG) / (CRATE_MAX_KG - CRATE_MIN_KG) * 0.55 -- 0.8…1.35
end

-- special-tier look: repaint + materials (body / lid separately) + idle sparkles + tinted hover tag
local function applyTierLook(crate, main, bodyColor, lidColor, material, lidMaterial, tagText)
	for _, p in ipairs(crate:GetDescendants()) do
		if p:IsA("BasePart") then
			local isLid = (p.Name == "Lid")
			p.Color = isLid and lidColor or bodyColor
			pcall(function() p.Material = isLid and lidMaterial or material end)
		end
	end
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, main.Size.Y / 2, 0)
	att.Parent = main
	local sp = Instance.new("ParticleEmitter") -- lazy glints so it reads as special from afar
	sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sp.Color = ColorSequence.new(lidColor, Color3.fromRGB(255, 255, 255))
	sp.LightEmission = 1
	sp.Size = NumberSequence.new(0.45, 0.1)
	sp.Lifetime = NumberRange.new(0.6, 1.0)
	sp.Speed = NumberRange.new(1.5, 3)
	sp.SpreadAngle = Vector2.new(60, 60)
	sp.Rate = 4
	sp.Parent = att
	local label = main:FindFirstChild("CrateLabel")
	local ct = label and label:FindFirstChild("ContentText")
	if ct then ct.Text = tagText; ct.TextColor3 = lidColor end
end

local function applyCrateStats(crate, main, weight, golden, diamond)
	crate:SetAttribute("WeightKg", weight)
	local label = main:FindFirstChild("CrateLabel")
	local wl = label and label:FindFirstChild("WeightText")
	if wl then wl.Text = string.format("%.1f кг", weight) end
	if diamond then
		crate:SetAttribute("Diamond", true)
		-- metal body like the golden one, with a GLOWING ice-blue lid
		applyTierLook(crate, main, DIAMOND_COLOR, DIAMOND_LID_COLOR, Enum.Material.Metal, Enum.Material.Neon, "Алмазный ящик")
	elseif golden then
		crate:SetAttribute("Golden", true)
		applyTierLook(crate, main, GOLD_COLOR, GOLD_LID_COLOR, Enum.Material.Metal, Enum.Material.Metal, "Золотой ящик")
	end
end

local function carryCrate(state)
	if state.heldCrate then return end
	local hand = handPart(findRig(state.diver))
	local crate = buildCrate()
	local main = crate.PrimaryPart
	if hand and main then
		crate:PivotTo(hand.CFrame * CFrame.new(0, -1.0, 0))
		crate.Parent = workspace
		local w = Instance.new("WeldConstraint"); w.Part0 = main; w.Part1 = hand; w.Parent = main
		-- roll the stats NOW: a special crate looks special already in his hands, and the carried
		-- crate is physically sized by its weight
		local weight, golden, diamond = rollCrateStats()
		applyCrateStats(crate, main, weight, golden, diamond)
		pcall(function() crate:ScaleTo(crateScaleFor(weight)) end)
		state.heldCrate = crate
	else
		crate:Destroy()
	end
end

-- THE delivery: spawn a fresh crate ON THE DECK and weld it there. If a world `dropPos` is given (the
-- spot in FRONT of the diver as he throws), use that; otherwise fall back to the authored crate spot.
-- Zero flight → it can never end up in the sky or the sea.
local function deliverCrateAtMonolith(dropPos, content, weightKg, golden, diamond)
	local base = rpp()
	if not base then return end
	local spot
	if dropPos then
		local a = math.random() * math.pi * 2
		local r = 0.4 + math.random() * 1.8
		spot = dropPos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	elseif crateLocalNow() then
		-- the authored crate spot in the world, then scatter in WORLD-horizontal space (the raft's local
		-- frame is a tilted cylinder, so a local offset would push crates UP, not sideways)
		local base0 = base.CFrame:PointToWorldSpace(crateLocalNow())
		local a = math.random() * math.pi * 2
		local r = 1 + math.random() * 2.5
		spot = base0 + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	else
		local mono = monolithPivot()
		local cx, cz = base.Position.X, base.Position.Z
		if mono then cx, cz = mono.X, mono.Z end
		spot = Vector3.new(cx + 3, base.Position.Y + 3, cz)
	end
	-- 25%: вместо обычного ящика дайвер приносит ЯЩИК С ПАТРОНАМИ (физическая модель на палубе)
	if _G.SpawnAmmoCase and math.random() < AMMO_CASE_CHANCE then
		crateDropFX(spot)
		--[[ ⚠️ НИЗ ЯЩИКА — НА НАСТИЛ, А НЕ НА «spot + 1.2».
		     Обычный ящик ставится центром в spot и варится к плоту, ему высота не
		     важна. Ящик с патронами ставится НИЗОМ габарита в переданную точку, и
		     прибавка 1.2 студа поднимала его в воздух. Ищем настил лучом вниз по
		     самому плоту и ставим низ ровно на него; плота под точкой нет — на
		     высоту обычного ящика. ]]
		local floor = spot
		local raftModel = base.Parent
		if raftModel then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { raftModel }
			local hit = workspace:Raycast(spot + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), params)
			if hit then floor = hit.Position end
		end
		_G.SpawnAmmoCase(CFrame.new(floor), "deck")
		return
	end

	local crate = buildCrate(content)
	local main = crate.PrimaryPart or crate:FindFirstChildWhichIsA("BasePart")
	if not main then crate:Destroy(); return end
	crate.Parent = workspace
	parkCrate(crate, main, spot)

	-- stats are INHERITED from the crate the diver carried (rolled at surface time); the roll here
	-- only covers direct deliveries that never had a held prop
	local weight = tonumber(weightKg)
	if not weight or golden == nil or diamond == nil then
		local w, g, d = rollCrateStats()
		weight = weight or w
		if golden == nil then golden = g end
		if diamond == nil then diamond = d end
	end
	applyCrateStats(crate, main, weight, golden, diamond)

	crateDropFX(spot)
	cratePopIn(crate, crateScaleFor(weight))
end

-- "release": the held prop fades out of his hand and the REAL crate appears welded on the deck —
-- with the SAME content, weight and golden-ness as the one he carried
local function releaseCrate(state, dropPos)
	local held = state.heldCrate
	state.heldCrate = nil
	local content = held and held:GetAttribute("Content") or nil
	local weight = held and held:GetAttribute("WeightKg") or nil
	local golden, diamond = nil, nil -- nil = "no held crate, roll at delivery"; false must stay false
	if held then
		golden = held:GetAttribute("Golden") == true
		diamond = held:GetAttribute("Diamond") == true
	end
	if held and held.Parent then fadeAndRemove(held, 0.2) end
	deliverCrateAtMonolith(dropPos, content, weight, golden, diamond)
end

-- Throw the crate down IN FRONT of him and only THEN turn away. He keeps his ARRIVAL facing (he walked
-- in already facing his spot / the monolith), so there is NO pre-turn — he places, then the loop turns
-- him back toward the edge. The crate drops at his feet-forward point on the deck, computed at release.
local function throwCrate(state, tracks)
	local hrp = state.hrp
	local rig = findRig(state.diver)
	local hipH = state.hip or 3
	local function frontDrop()
		local lv = hrp.CFrame.LookVector
		local look = Vector3.new(lv.X, 0, lv.Z)
		look = (look.Magnitude > 0.1) and look.Unit or Vector3.new(1, 0, 0)
		return Vector3.new(hrp.Position.X + look.X * 3, hrp.Position.Y - hipH + 1.1, hrp.Position.Z + look.Z * 3)
	end
	local track = tracks.throw
	if track then pcall(function() track:Play(0.1) end) end
	local joint, baseC0 = armJoint(rig)
	local released = false
	resetCarry(state)
	local t0 = os.clock()
	while os.clock() - t0 < THROW_TIME and alive(state) do
		RunService.Heartbeat:Wait()
		carryByRaft(state) -- stay put RELATIVE TO THE DECK while swinging (the raft sails on); no re-facing
		local a = (os.clock() - t0) / THROW_TIME
		if joint and not track then
			local ang
			if a < 0.45 then ang = math.rad(-100) * (a / 0.45)
			elseif a < 0.70 then ang = math.rad(-100) + math.rad(180) * ((a - 0.45) / 0.25)
			else ang = math.rad(80) * (1 - (a - 0.70) / 0.30) end
			joint.C0 = baseC0 * CFrame.Angles(ang, 0, 0)
		end
		if not released and a >= 0.55 then released = true; releaseCrate(state, frontDrop()) end
	end
	if joint and baseC0 then joint.C0 = baseC0 end
	if track then pcall(function() track:Stop(0.15) end) end
	if state.heldCrate then releaseCrate(state, frontDrop()) end -- hard guarantee: crate never stays in hand
end

-- ── movement phases (anchored-root kinematics) ──
-- walk on the deck toward worldTargetFn() (XZ); Y always = real deck + measured hip.
-- Rides the raft (carryByRaft) so his walk is relative to the deck, no sliding.
local function walkDeck(state, worldTargetFn, track, reach, timeout)
	playT(track)
	resetCarry(state)
	local t0 = os.clock()
	while alive(state) do
		local dt = RunService.Heartbeat:Wait()
		carryByRaft(state)
		local pos = state.hrp.Position
		local target = worldTargetFn()
		if not target then break end
		local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
		local d = flat.Magnitude
		if d <= (reach or 2.5) then break end
		local dir = flat.Unit
		local step = math.min(WALK_SPEED * dt, d)
		local nx, nz = pos.X + dir.X * step, pos.Z + dir.Z * step
		local dy = deckYAt(nx, nz, true)
		if not dy then break end -- NO logs under the next step → deck edge reached; NEVER walk on air
		place(state.hrp, Vector3.new(nx, dy + state.hip, nz), dir)
		if os.clock() - t0 > (timeout or 15) then break end
	end
	stopT(track)
end

-- swim at the water surface toward worldTargetFn() (XZ)
local function swimTo(state, worldTargetFn, track, reach, timeout)
	playT(track)
	local t0 = os.clock()
	while alive(state) do
		local dt = RunService.Heartbeat:Wait()
		local pos = state.hrp.Position
		local target = worldTargetFn()
		if not target then break end
		local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
		local d = flat.Magnitude
		if d <= (reach or 3) then break end
		local dir = flat.Unit
		local step = math.min(SWIM_SPEED * dt, d)
		local nx, nz = pos.X + dir.X * step, pos.Z + dir.Z * step
		local wy = waterYAt(nx, nz, { state.diver, state.heldCrate }) + SWIM_Y_OFFSET
		place(state.hrp, Vector3.new(nx, wy, nz), dir)
		if os.clock() - t0 > (timeout or 30) then break end
	end
	stopT(track)
end

-- a smooth kinematic arc from the current position to toFn() over dur seconds
local function arcTo(state, toFn, dur, peak, track)
	playT(track, 0.05)
	local from = state.hrp.Position
	local t0 = os.clock()
	while alive(state) do
		RunService.Heartbeat:Wait()
		local a = math.clamp((os.clock() - t0) / dur, 0, 1)
		local to = toFn() or from
		local pos = from:Lerp(to, a) + Vector3.new(0, math.sin(math.pi * a) * peak, 0)
		local dir = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
		place(state.hrp, pos, dir.Magnitude > 0.05 and dir.Unit or nil)
		if a >= 1 then break end
	end
	stopT(track, 0.15)
end

-- vertical drift (submerge / surface)
local function driftY(state, fromY, toY, dur, track)
	playT(track)
	local t0 = os.clock()
	while alive(state) do
		RunService.Heartbeat:Wait()
		local a = math.clamp((os.clock() - t0) / dur, 0, 1)
		local p = state.hrp.Position
		place(state.hrp, Vector3.new(p.X, fromY + (toY - fromY) * a, p.Z), nil)
		if a >= 1 then break end
	end
end

-- ── ONE full trip. WORLD-SPACE math only. The raft's PrimaryPart is a ROTATED CYLINDER, so its local
-- axes are NOT world up/right — decomposing raft-local X/Z as "horizontal" sent him climbing into the
-- sky. So: horizontal directions are computed in WORLD space, deck-riding is done with carryByRaft()
-- (which applies the raft's rigid frame-to-frame motion, tilt and all → correct at any orientation),
-- and vertical positions come from waterYAt (sea) or standWorld().Y (his authored deck+hip height).
local function gatherTrip(state, tracks)
	local diver, hrp = state.diver, state.hrp
	local base = rpp()
	if not base or not standLocalNow() then task.wait(1); return end
	if not monolithOnRaft() then task.wait(1); return end   -- тотем унесён с плота: ждём, пока вернут
	clearDiverWeld(hrp) -- take kinematic control for the moving phases
	local hip = state.hip

	local function phase(n)
		diver:SetAttribute("Phase", n)
		if state.badge then state.badge.Text = n end
	end
	local function bail()
		if state.abort then state.abort = false; return true end
		return false
	end
	local function center() local b = rpp(); return b and b.Position or hrp.Position end
	-- his authored stance in the world RIGHT NOW (rides the raft rigidly; upright regardless of tilt)
	-- each diver has his OWN spot: the authored stand pose shifted sideways in the STAND frame
	-- (upright, so the offset is safe — never decompose the tilted raft-PP frame!)
	local standOff = state.standOff or CFrame.new()
	local function standWorld() local b = rpp(); return b and (b.CFrame * standLocalNow() * standOff) or hrp.CFrame end
	-- world-horizontal unit vector pointing radially OUT from the raft center through the diver
	local function outDirNow()
		local c, p = center(), hrp.Position
		local f = Vector3.new(p.X - c.X, 0, p.Z - c.Z)
		return (f.Magnitude > 0.5) and f.Unit or Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
	end

	-- guarantee: never run around with a crate — deliver a leftover immediately
	if state.heldCrate then releaseCrate(state) end

	-- 1) WALK outward across the deck a short, bounded distance (never past the edge), riding the raft.
	-- carryByRaft handles ALL raft motion incl. the vertical bob → his deck height stays right with NO
	-- raycast and NO local-frame decomposition (the cause of the "walks up into the air" bug).
	phase("toEdge")
	do
		playT(tracks.walk)
		resetCarry(state)
		local moved, cap = 0, 30 -- generous cap; the REAL stopper is the whole-raft deck-edge probe below
		while alive(state) and moved < cap do
			local dt = RunService.Heartbeat:Wait()
			carryByRaft(state) -- ride the sailing/bobbing raft (tilt-agnostic) → horizontal drift
			local outDir = outDirNow()
			local step = math.min(WALK_SPEED * dt, cap - moved)
			local p = hrp.Position
			local nx, nz = p.X + outDir.X * step, p.Z + outDir.Z * step
			local refY = standWorld().Position.Y - hip
			local dy = deckHitY(nx, nz, refY) -- built floor included; nil once past the TRUE edge
			if not dy then break end          -- reached the real edge → stop here, then jump
			place(hrp, Vector3.new(nx, dy + hip, nz), outDir) -- stand ON the actual floor
			moved = moved + step
		end
		stopT(tracks.walk)
	end
	if bail() then return end

	-- pause at the edge
	phase("pause")
	do
		resetCarry(state)
		local t0 = os.clock()
		while alive(state) and os.clock() - t0 < IDLE_AT_EDGE do RunService.Heartbeat:Wait(); carryByRaft(state) end
	end
	if bail() then return end

	-- 2) jump off into the water (static landing, computed once)
	phase("jump")
	local ow = outDirNow()
	local jx, jz = hrp.Position.X + ow.X * JUMP_DIST, hrp.Position.Z + ow.Z * JUMP_DIST
	local landing = Vector3.new(jx, waterYAt(jx, jz, { diver }) + SWIM_Y_OFFSET, jz)
	arcTo(state, function() return landing end, 0.6, JUMP_HEIGHT, tracks.jump)
	splashAt(hrp.Position)
	if bail() then return end

	-- 3) swim outward on the surface for a fixed few seconds (visible swim), THEN sink
	phase("swimOut")
	local swimDir = ow
	playT(tracks.swim)
	local st = os.clock()
	while alive(state) and os.clock() - st < SWIM_OUT_SECONDS do
		local dt = RunService.Heartbeat:Wait()
		local p = hrp.Position
		local nx, nz = p.X + swimDir.X * SWIM_SPEED * dt, p.Z + swimDir.Z * SWIM_SPEED * dt
		local wy = waterYAt(nx, nz, { diver }) + SWIM_Y_OFFSET
		place(hrp, Vector3.new(nx, wy, nz), swimDir)
	end
	stopT(tracks.swim)
	if bail() then return end

	-- 4) sink SLOWLY, then wait out the timer following the raft underwater (ring outside the guard box)
	phase("underwater")
	local surfY = waterYAt(hrp.Position.X, hrp.Position.Z, { diver }) + SWIM_Y_OFFSET
	driftY(state, surfY, surfY - SUBMERGE_DEPTH, SINK_TIME, tracks.swim)
	nextDeliveryAt = os.clock() + DELIVERY_INTERVAL
	skipRequested = false
	playT(tracks.swim)
	while os.clock() < nextDeliveryAt and alive(state) and not skipRequested do
		local dt = RunService.Heartbeat:Wait()
		local b = rpp()
		if b then
			local off = Vector3.new(hrp.Position.X - b.Position.X, 0, hrp.Position.Z - b.Position.Z)
			off = (off.Magnitude > 1) and off.Unit or Vector3.new(1, 0, 0)
			local ring = Vector3.new(b.Position.X, 0, b.Position.Z) + off * 26
			local wy = waterYAt(ring.X, ring.Z, { diver }) - SUBMERGE_DEPTH
			local goal = Vector3.new(ring.X, wy, ring.Z)
			local delta = goal - hrp.Position
			local step = math.min(SWIM_SPEED * dt, delta.Magnitude)
			if step > 0.01 then place(hrp, hrp.Position + delta.Unit * step, Vector3.new(delta.X, 0, delta.Z)) end
		end
	end
	stopT(tracks.swim)
	if state.dead or not diver.Parent then return end
	if bail() then return end
	while crateCount >= MAX_CRATES and alive(state) do RunService.Heartbeat:Wait() end

	-- 5) surface SLOWLY, crate in hand
	phase("surface")
	carryCrate(state)
	local p = hrp.Position
	local sy = waterYAt(p.X, p.Z, { diver, state.heldCrate }) + SWIM_Y_OFFSET
	driftY(state, p.Y, sy, SURFACE_TIME, tracks.swim)
	splashAt(hrp.Position)
	if bail() then return end

	-- 6) swim back toward the raft until he's just off the real deck edge (probe the actual deck)
	phase("swimBack")
	swimTo(state, function()
		local b = rpp(); if not b then return nil end
		return b.Position -- head for the raft center; the reach check stops him just outside the edge
	end, tracks.swim, deckRadius() + 3, 20)
	-- keep closing until a downward probe a little ahead finds real deck (built floor included)
	do
		local refY = standWorld().Position.Y - hip
		local t0 = os.clock()
		playT(tracks.swim)
		while alive(state) and os.clock() - t0 < 4 do
			local b = rpp(); if not b then break end
			local inDir = Vector3.new(b.Position.X - hrp.Position.X, 0, b.Position.Z - hrp.Position.Z)
			inDir = (inDir.Magnitude > 0.5) and inDir.Unit or Vector3.new(1, 0, 0)
			-- deck within ~4 studs ahead? then we're at the edge, stop swimming and climb
			if deckHitY(hrp.Position.X + inDir.X * 4, hrp.Position.Z + inDir.Z * 4, refY, 3.5) then break end
			local dt = RunService.Heartbeat:Wait()
			local nx, nz = hrp.Position.X + inDir.X * SWIM_SPEED * dt, hrp.Position.Z + inDir.Z * SWIM_SPEED * dt
			local wy = waterYAt(nx, nz, { diver, state.heldCrate }) + SWIM_Y_OFFSET
			place(hrp, Vector3.new(nx, wy, nz), inDir)
		end
		stopT(tracks.swim)
	end
	if bail() then return end

	-- 7) climb: probe inward for the REAL deck footing and arc up ONTO it. The landing is stored raft-
	-- relative so it rides the sailing raft during the arc (a static world point would drift to water).
	phase("climb")
	local climbRelCF
	do
		local b = rpp()
		local inDir = Vector3.new(b.Position.X - hrp.Position.X, 0, b.Position.Z - hrp.Position.Z)
		inDir = (inDir.Magnitude > 0.5) and inDir.Unit or Vector3.new(1, 0, 0)
		local refY = standWorld().Position.Y - hip
		local landing
		local d = 1
		while d <= 16 do
			local px, pz = hrp.Position.X + inDir.X * d, hrp.Position.Z + inDir.Z * d
			local dy = deckHitY(px, pz, refY, 3.5)
			if dy then landing = Vector3.new(px, dy + hip, pz); break end
			d = d + 1.5
		end
		landing = landing or Vector3.new(hrp.Position.X + inDir.X * 5, standWorld().Position.Y, hrp.Position.Z + inDir.Z * 5)
		climbRelCF = b.CFrame:ToObjectSpace(CFrame.new(landing))
	end
	arcTo(state, function()
		local b = rpp(); return b and (b.CFrame * climbRelCF).Position or hrp.Position
	end, CLIMB_TIME, JUMP_HEIGHT, tracks.jump)
	if bail() then return end

	-- 8) WALK in to his authored spot (live target rides the raft; Y = authored deck+hip), then throw
	phase("toMono")
	do
		playT(tracks.walk)
		resetCarry(state)
		local t0 = os.clock()
		while alive(state) do
			local dt = RunService.Heartbeat:Wait()
			carryByRaft(state) -- ride the raft so he isn't fighting its translation while closing in
			local sw = standWorld().Position
			local pp = hrp.Position
			local flat = Vector3.new(sw.X - pp.X, 0, sw.Z - pp.Z)
			local d = flat.Magnitude
			if d <= 1.5 or os.clock() - t0 > 5 then break end
			local dir = flat.Unit
			local step = math.min(WALK_SPEED * dt, d)
			place(hrp, Vector3.new(pp.X + dir.X * step, sw.Y, pp.Z + dir.Z * step), dir)
		end
		stopT(tracks.walk)
	end
	if bail() then return end

	phase("throw")
	if not state.dead then throwCrate(state, tracks) end
	if state.heldCrate then releaseCrate(state) end
	-- beat AFTER placing (facing the crate) BEFORE the loop turns him back to the edge → "place, then turn"
	local b0 = os.clock()
	resetCarry(state)
	while os.clock() - b0 < 1.0 and alive(state) do RunService.Heartbeat:Wait(); carryByRaft(state) end
	-- loop: back to the edge and dive again
end

-- Right after he stands up, let him "come to": a couple of casual strolls around the deck (staying on
-- real floor) with idle beats, BEFORE the gather loop marches him to the edge to dive.
local function recoveryWander(state, tracks)
	local hrp, hip = state.hrp, state.hip
	local function refY()
		local b = rpp()
		if b and standLocalNow() then return (b.CFrame * standLocalNow()).Position.Y - hip end
		return hrp.Position.Y - hip
	end
	local function idle(t)
		local t0 = os.clock()
		while alive(state) and os.clock() - t0 < t do RunService.Heartbeat:Wait() end
	end
	idle(0.7) -- catch his breath
	for _ = 1, 3 do
		if not alive(state) then break end
		local ang = math.random() * math.pi * 2
		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local goal = 3 + math.random() * 3 -- a short 3–6 stud stroll
		if state.badge then state.badge.Text = "восстановить" end
		playT(tracks.walk)
		local moved = 0
		while alive(state) and moved < goal do
			local dt = RunService.Heartbeat:Wait()
			local p = hrp.Position
			local step = WALK_SPEED * dt
			local nx, nz = p.X + dir.X * step, p.Z + dir.Z * step
			local dy = deckHitY(nx, nz, refY())
			if not dy then break end -- reached the deck edge → don't wander off, end this stroll
			place(hrp, Vector3.new(nx, dy + hip, nz), dir)
			moved = moved + step
		end
		stopT(tracks.walk)
		idle(0.4 + math.random() * 0.5)
	end
end

local function startGatherLoop(diver, hum, hrp, tracks, hip, standOff)
	local state = { diver = diver, hum = hum, hrp = hrp, dead = false, abort = false, heldCrate = nil,
		hip = hip, standOff = standOff }
	-- Отладочная табличка фазы над головой убрана: водолаз работает без неё
	-- (владелец: «убери состояния над головой»). state.badge остаётся nil, все
	-- записи в него ниже защищены проверкой.
	diverWorking = true
	diver.Destroying:Connect(function()
		state.dead = true
		diverWorking = false
		if state.heldCrate then pcall(function() state.heldCrate:Destroy() end); state.heldCrate = nil end
	end)
	-- WATCHDOG: whatever else happens, he can NEVER run away — too far from the raft or too high →
	-- snapped underwater beside the raft and the trip restarts with a fresh approach
	task.spawn(function()
		while diver.Parent and not state.dead do
			task.wait(0.5)
			local b = rpp()
			if b then
				local p = hrp.Position
				local flat = Vector3.new(p.X - b.Position.X, 0, p.Z - b.Position.Z)
				local tooFar = flat.Magnitude > 120
				local tooHigh = p.Y > b.Position.Y + 15
				-- NOTE: no "walking on air" check any more — there is no deck walking, and the deck
				-- raycast falsely flagged his legit stand spot (raft logs collide via invisible boxes),
				-- which yanked him underwater in an endless loop.
				if tooFar or tooHigh then
					local why = tooFar and "too far" or "too high"
					warn(("[DiverSystem] WATCHDOG: diver ran away (%s, phase %s, pos %d,%d,%d) — snapping back")
						:format(why, tostring(diver:GetAttribute("Phase")), p.X, p.Y, p.Z))
					local off = (flat.Magnitude > 1) and flat.Unit or Vector3.new(1, 0, 0)
					local ring = Vector3.new(b.Position.X, 0, b.Position.Z) + off * (deckRadius() + 8)
					weldDiverAt(hrp, CFrame.lookAt(
						Vector3.new(ring.X, b.Position.Y - 6, ring.Z),
						Vector3.new(b.Position.X, b.Position.Y - 6, b.Position.Z)))
					state.abort = true -- phase loops exit; gatherTrip bails; a clean approach restarts
				end
			end
		end
	end)
	task.spawn(function()
		-- one-time "come to" wander after standing up, then the normal dive loop
		pcall(function() recoveryWander(state, tracks) end)
		state.abort = false
		while diver.Parent and not state.dead do
			local ok, err = pcall(function() gatherTrip(state, tracks) end)
			if not ok then warn("[DiverSystem] trip error: " .. tostring(err)); task.wait(1) end
			state.abort = false
		end
	end)
	return state
end

-- ── status for the monolith timer UI ──
_G.DiverActive = function() return diverWorking end
_G.DiverSecondsLeft = function()
	if not diverWorking then return nil end
	return math.max(0, nextDeliveryAt - os.clock())
end
_G.SkipDiverTimer = function()
	skipRequested = true
	nextDeliveryAt = os.clock()
end

-- ── starter diver: lies by the monolith until PURCHASED ──
local starter = nil

local function reviveStarter()
	local s = starter
	if not s or s.revived then return end
	s.revived = true
	s.lying = false               -- stops the lying-animation reassert loop
	diverWorking = true           -- the monolith is repaired → he's on duty (click shows the timer)
	task.spawn(function()
		burstAt(s.hrp.Position, true)
		-- he stays WELDED to the raft the whole time he gets up (rigid → no jitter). The Revive
		-- animation plays the GET-UP from the lying pose; we only re-pin him standing AFTER it finishes,
		-- so he never snaps upright instantly. (Before he stood the moment the lie pose stopped.)
		local rev = s.tracks.revive
		-- dedicated fallback search: the get-up may be named anything getup-ish (NOT "before"/"live")
		if not rev then
			local animator = s.hum:FindFirstChildOfClass("Animator")
			local patterns = { "reviv", "getup", "get_up", "get up", "standup", "stand_up", "stand up",
				"wake", "awaken", "rise", "arise", "resurrect", "spawn", "born", "up" }
			if animator then
				for _, d in ipairs(s.diver:GetDescendants()) do
					if d:IsA("Animation") and d.AnimationId ~= "" then
						local ln = d.Name:lower()
						if not ln:find("before") and not ln:find("swim") and not ln:find("walk")
							and not ln:find("run") and not ln:find("jump") then
							for _, pat in ipairs(patterns) do
								if ln:find(pat) then
									local okL, tr = pcall(function() return animator:LoadAnimation(d) end)
									if okL and tr then rev = tr end
									break
								end
							end
						end
					end
					if rev then break end
				end
			end
		end
		if rev then
			rev.Looped = false
			-- Make sure Revive is LOADED before it ever becomes dominant. An unloaded track poses an empty
			-- (rest = standing) pose, so warm it at the LOWEST priority (Core) where it can't override the
			-- Action3 lie, then stop it.
			if rev.Length <= 0.05 then
				rev.Priority = Enum.AnimationPriority.Core
				pcall(function() rev:Play(0) end)
				local t0 = os.clock()
				while os.clock() - t0 < 6 and rev.Length <= 0.05 do RunService.Heartbeat:Wait() end
				pcall(function() rev:Stop(0) end)
				RunService.Heartbeat:Wait()
			end
			print(("[DiverSystem] revive: loaded=%s length=%.2f"):format(tostring(rev.Length > 0.05), rev.Length))
			if rev.Length > 0.05 then
				-- Play Revive ONE PRIORITY ABOVE the still-playing frozen lie (Action4 over Action3). Revive
				-- frame 0 IS the lying pose (confirmed), so it OVERRIDES the lie with an IDENTICAL pose →
				-- zero rise. The lie is NEVER stopped during the get-up, so the RootJoint is never left at
				-- its default for a frame (that default snap-to-root was the "1 ms rise"). No gap, no blend.
				rev.Priority = Enum.AnimationPriority.Action4
				rev.Looped = false
				pcall(function() rev.TimePosition = 0; rev:AdjustSpeed(1); rev:Play(0.12) end)
				-- ONE clock from the moment Play started. The old code measured length for 0.4s BEFORE
				-- starting its timer, so it kept waiting past the clip's real end — the non-looped track
				-- had auto-stopped by then, nothing posed at Action4 for ~0.3s and the Action3 lie
				-- underneath took over (the "lies back down for a beat, then stands" bug). Length is
				-- refined inside the same loop, and we FREEZE the final frame BEFORE the track can stop.
				-- play the clip TO ITS LAST FRAME, tracked by the track's own TimePosition (a wall clock
				-- undershot by ~0.1s and cut the ending), then freeze IN PLACE — no skipped tail
				local playStart = os.clock()
				local total = rev.Length
				while s.diver.Parent do
					rev.Looped = false
					if rev.Length > total then total = rev.Length end
					if not rev.IsPlaying or rev.TimePosition >= total - 0.02 then break end
					if os.clock() - playStart > total + 1 then break end -- hard safety cap
					RunService.Heartbeat:Wait()
				end
				print(("[DiverSystem] revive length=%.2f"):format(total))
				if rev.IsPlaying then
					pcall(function() rev:AdjustSpeed(0) end) -- freeze exactly where it is (the last frame)
				else
					-- auto-stopped on the frame boundary → re-pin the last frame immediately
					pcall(function() rev:Play(0.05); rev:AdjustSpeed(0); rev.TimePosition = math.max(0, total - 0.02) end)
				end
				task.wait(0.6) -- settle beat, held in the final standing pose
				weldDiverAt(s.hrp, s.standWorld())     -- lock the exact standing stance at the end
				if s.beforeTrack then pcall(function() s.beforeTrack:Stop(0) end) end -- NOW drop the overridden lie
				-- FULLY stop Revive. It was frozen (AdjustSpeed 0) at Action4 — Stop can fail to take on a
				-- frozen track, leaving it dominant and OVERRIDING every lower-priority movement animation
				-- (walk/jump/swim are Action). Unfreeze first so Stop actually ends it.
				pcall(function() rev:AdjustSpeed(1); rev:Stop(0.15) end)
			else
				-- Revive never loaded (AnimationId not authorized / still processing after a re-upload)
				warn("[DiverSystem] Revive did not load — smooth rise fallback. If you just re-uploaded the "
					.. "animation, its AnimationId isn't usable yet (must be owned by this game's creator).")
				if s.beforeTrack then pcall(function() s.beforeTrack:Stop(1.0) end) end
				task.wait(1.0)
				weldDiverAt(s.hrp, s.standWorld())
			end
		else
			warn("[DiverSystem] no get-up animation matched — using a SMOOTH RISE. Check the "
				.. "'[DiverSystem] rig animations' line printed at startup and tell me the get-up's exact name.")
			-- smooth rise: fade the frozen lying pose out over ~1s so the body blends UP to the standing
			-- rest pose (a gentle get-up) instead of snapping. Not the real animation, but not a hard cut.
			if s.beforeTrack then pcall(function() s.beforeTrack:Stop(1.0) end) end
			task.wait(1.0)
			weldDiverAt(s.hrp, s.standWorld())
		end
		burstAt(s.hrp.Position, true)
		startGatherLoop(s.diver, s.hum, s.hrp, s.tracks, s.hip)
	end)
end

-- repairing the monolith is what wakes him (per design). Buying also works if the shop is ever used.
_G.OnMonolithRepaired = reviveStarter

local extraDivers = 0 -- clones beyond the starter (the "Кол-во дайверов" upgrade)

_G.SpawnDiver = function()
	if starter and not starter.revived then
		burstAt(starter.hrp.Position, true)
		reviveStarter()
		return starter.diver
	end
	-- extra divers ("Кол-во дайверов" upgrade): clone the rig and give him his OWN spot — the
	-- starter's authored stance shifted sideways in the (upright) stand frame
	local tmpl = AssetFind.find(DIVER_TEMPLATE)
	if not tmpl then warn("[DiverSystem] no '" .. DIVER_TEMPLATE .. "' in ReplicatedStorage"); return nil end
	local diver = tmpl:Clone(); diver.Name = DIVER_TEMPLATE
	diver.Parent = workspace
	local hum, hrp, tracks = setupDiver(diver)
	if not hum then diver:Destroy(); return nil end
	extraDivers += 1
	local standOff = CFrame.new(-3.5 * extraDivers, 0, 0) -- side by side with the starter
	local hip = (starter and starter.hip) or 3
	local base = rpp()
	if base and standLocalNow() then
		hrp.CFrame = base.CFrame * standLocalNow() * standOff
	else
		local mono = monolithPivot() or (base and base.Position)
		if not mono then diver:Destroy(); return nil end
		hrp.CFrame = CFrame.new(mono.X + 4 + 3 * extraDivers, mono.Y + hip, mono.Z)
	end
	burstAt(hrp.Position, true)
	startGatherLoop(diver, hum, hrp, tracks, hip, standOff)
	return diver
end

task.spawn(function()
	local diver
	for _ = 1, 60 do
		for _, d in ipairs(workspace:GetChildren()) do
			if d:IsA("Model") and d.Name == DIVER_TEMPLATE then diver = d; break end
		end
		if diver and rpp() then break end
		task.wait(0.5)
	end
	if not diver then
		warn("[DiverSystem] no '" .. DIVER_TEMPLATE .. "' model in Workspace — starter disabled")
		return
	end
	local hum, hrp, tracks = setupDiver(diver)
	if not hum then return end

	-- DEBUG: dump EVERY animation on the rig (name + id + where it lives) so we can identify the exact
	-- get-up ("Revive") animation — the searches by name kept coming up empty, so print the ground truth.
	do
		local list = {}
		for _, d in ipairs(diver:GetDescendants()) do
			if d:IsA("Animation") then
				table.insert(list, ("%s [id=%s, in=%s]"):format(d.Name, tostring(d.AnimationId), d.Parent and d.Parent.Name or "?"))
			end
		end
		print("[DiverSystem] rig animations (" .. #list .. "): " .. (#list > 0 and table.concat(list, "  |  ") or "NONE as Animation objects"))
	end

	-- PRELOAD every rig animation now so the get-up ("Revive") is fully cached long before the player
	-- ever repairs the monolith → at revive time it plays instantly (no streaming gap = no empty-pose
	-- "stand up before the animation").
	task.spawn(function()
		local anims = {}
		for _, d in ipairs(diver:GetDescendants()) do
			if d:IsA("Animation") and d.AnimationId ~= "" then table.insert(anims, d) end
		end
		if #anims > 0 then pcall(function() game:GetService("ContentProvider"):PreloadAsync(anims) end) end
	end)

	-- ground truth from the AUTHORED placement: his hip height above the real deck
	local authored = hrp.CFrame
	local deckHere = deckYAt(authored.Position.X, authored.Position.Z)
	local hip = deckHere and math.clamp(authored.Position.Y - deckHere, 1.5, 4.5) or 3

	local base = rpp()
	local standLocal = base and base.CFrame:ToObjectSpace(authored) or authored
	local function standWorld()
		local b = rpp()
		return b and (b.CFrame * standLocal) or authored
	end

	-- publish the authored GROUND TRUTH for the whole system (loop + crate delivery)
	G_standLocal = standLocal
	do local mf = monolithFrame(); if mf then MonoRel.stand = mf:ToObjectSpace(authored) end end
	if base then
		local mono = monolithPivot()
		local crateWorld
		if mono then
			-- 40% of the way from his spot toward the monolith, at crate-rest height
			crateWorld = authored.Position:Lerp(Vector3.new(mono.X, authored.Position.Y, mono.Z), 0.4)
		else
			crateWorld = authored.Position + authored.LookVector * 2.5
		end
		crateWorld = Vector3.new(crateWorld.X, authored.Position.Y - hip + 1.15, crateWorld.Z)
		G_crateLocal = base.CFrame:PointToObjectSpace(crateWorld)
		do local mf = monolithFrame(); if mf then MonoRel.crate = mf:PointToObjectSpace(crateWorld) end end
	end

	starter = { diver = diver, hum = hum, hrp = hrp, tracks = tracks, revived = false, hip = hip,
		standWorld = standWorld, lying = true }

	-- LIE at his authored spot until the monolith is repaired. He is WELDED to the raft (rigid → no
	-- jitter), upright, and the "Before_live" lying animation poses the body. Roblox can silently reset
	-- track.Looped to the asset's baked value once it streams in, so we FORCE the loop by replaying it
	-- whenever it stops — this is why he used to stand up "at the end of the animation".
	local beforeTrack
	do
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		for _, d in ipairs(diver:GetDescendants()) do
			if d:IsA("Animation") and d.AnimationId ~= "" and d.Name:lower():find("before") then
				local okL, tr = pcall(function() return animator:LoadAnimation(d) end)
				if okL and tr then beforeTrack = tr end
				break
			end
		end
	end
	if beforeTrack then
		weldDiverAt(hrp, standWorld()) -- upright at his spot, welded (the animation lays him down)
		starter.beforeTrack = beforeTrack
		-- HOLD the lying pose by FREEZING the animation at its first frame (speed 0). This is immune to
		-- the Looped-flag reset that let him "get up at the very start", and works whether Before_live is
		-- a lie-loop or a get-up clip (frame 0 = lying either way). A playing, speed-0, top-priority track
		-- pins the pose forever — no end, no stop, no flicker.
		local function freezeLie()
			-- Action3 (one below the get-up's Action4) so Revive can cleanly OVERRIDE the lie without an
			-- equal-priority blend and without ever having to be stopped mid-transition.
			beforeTrack.Priority = Enum.AnimationPriority.Action3
			beforeTrack.Looped = false
			pcall(function() beforeTrack:Play(0.2) end)
			task.wait(0.08)
			pcall(function() beforeTrack:AdjustSpeed(0); beforeTrack.TimePosition = 0 end)
		end
		freezeLie()
		-- belt & suspenders: if anything ever stops it while he should still be lying, re-freeze
		beforeTrack.Stopped:Connect(function()
			if starter and starter.lying and not starter.revived and diver.Parent then task.spawn(freezeLie) end
		end)
	else
		-- no "Before_live" animation found → procedural flat lie: pitch the whole body and lower it to
		-- the deck (world-space translate — safe on the tilted-cylinder raft). Revive re-welds upright.
		warn("[DiverSystem] no 'Before_live' animation on the rig — using a procedural lying pose")
		local lieCF = (standWorld() * CFrame.Angles(math.rad(LIE_PITCH), 0, 0))
			- Vector3.new(0, math.max(0, hip - LIE_CLEAR), 0)
		weldDiverAt(hrp, lieCF)
	end
end)

print("[DiverSystem] ready (real-deck geometry)")

-- СЕЙВ: ящики на палубе. Лежат в Workspace, поэтому в плот не попадают — пишем отдельно.
_G.DiverExportCrates = function()
	local base = rpp()
	if not base then return {} end
	local out = {}
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("WeightKg") and not m:GetAttribute("_Taken") then
			local main = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
			if main and (main.Position - base.Position).Magnitude < 60 then
				local rel = base.CFrame:PointToObjectSpace(main.Position)
				table.insert(out, { x = rel.X, y = rel.Y, z = rel.Z, content = m:GetAttribute("Content"),
					weight = m:GetAttribute("WeightKg"), golden = m:GetAttribute("Golden") == true, diamond = m:GetAttribute("Diamond") == true })
			end
		end
	end
	return out
end
_G.DiverRestoreCrate = function(rec)
	local base = rpp()
	if not (base and type(rec) == "table") then return nil end
	local crate = buildCrate(rec.content)
	local main = crate.PrimaryPart or crate:FindFirstChildWhichIsA("BasePart")
	if not main then crate:Destroy(); return nil end
	crate.Parent = workspace
	local pos = base.CFrame:PointToWorldSpace(Vector3.new(rec.x or 0, rec.y or 3, rec.z or 0))
	parkCrate(crate, main, pos)
	local weight = tonumber(rec.weight) or 1
	applyCrateStats(crate, main, weight, rec.golden == true, rec.diamond == true)
	pcall(function() crate:ScaleTo(crateScaleFor(weight)) end)
	return crate
end
