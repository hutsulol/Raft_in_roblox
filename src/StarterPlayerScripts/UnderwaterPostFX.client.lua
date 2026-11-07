local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- Underwater screen effect: when the camera dips below the water surface,
-- fully blur and tint the screen so the player can't see through it.
-- The effect ignores the surface entirely; only true submersion triggers it.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local terrain = Workspace.Terrain

-- ─── Tunables ────────────────────────────────────────────────────────────────
local SUBMERGE_DEPTH = 2.5         -- studs below the water surface required to activate
local VOXEL_RES = 4                -- terrain voxel resolution (Roblox uses 4 studs per voxel)
local BLUR_SIZE = 56               -- how strong the blur is when underwater
local TINT_COLOR = Color3.fromRGB(0, 120, 140)
local SATURATION = -0.3
local CONTRAST = 0.05
local BRIGHTNESS = -0.1

-- ─── Lighting effects (created once) ─────────────────────────────────────────
local blur = Lighting:FindFirstChild("UnderwaterBlur")
if not blur then
	blur = Instance.new("BlurEffect")
	blur.Name = "UnderwaterBlur"
	blur.Size = 0
	blur.Parent = Lighting
end

local colorCorrection = Lighting:FindFirstChild("UnderwaterColor")
if not colorCorrection then
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "UnderwaterColor"
	colorCorrection.TintColor = TINT_COLOR
	colorCorrection.Saturation = SATURATION
	colorCorrection.Contrast = CONTRAST
	colorCorrection.Brightness = BRIGHTNESS
	colorCorrection.Enabled = false
	colorCorrection.Parent = Lighting
end

-- ─── State ───────────────────────────────────────────────────────────────────
-- Режимов три: суша, под водой БЕЗ маски (полная слепота), под водой В МАСКЕ.
-- ⚠️ МАСКА — ЭТО РАДИУС ВИДИМОСТИ, а не «та же муть послабее»: ровный блюр на
-- весь экран глушил и то, что перед носом («ничего не видно»). Правильно так:
-- вблизи ЧИСТО (DepthOfField держит фокус вокруг игрока), а вдаль — мгла
-- (туман + дальнее размытие). Никакого света и свечения — только видимость.
-- ⚠️ ЧЕТВЁРТЫЙ ЗАХОД, И НА ЭТОТ РАЗ ПРОСТО СВЕТЛЕЕ.
-- Три прошлых версии перечислены ниже; после них картинка стала правильной по
-- УСТРОЙСТВУ (чисто вблизи, мгла вдаль), но осталась тёмной по ощущению — маска
-- надета, а всё равно «плохо видно». Поэтому здесь двинуты только числа, а
-- устройство не тронуто: радиус чистой зоны почти вдвое дальше, дальний блюр
-- слабее, мгла начинает густеть позже и сама она светлее, плотность атмосферы
-- втрое ниже, яркость выше. Всё это ручки — крутить их тут, в одном месте.
local MASKED_CLEAR      = 18      -- студов чистой картинки от глаз: круг вокруг игрока
local MASKED_FAR_BLUR   = 0.85    -- размытие за радиусом (0..1)
local MASKED_SATURATION = -0.05
-- ⚠️ ТИНТ В МАСКЕ — СВЕТЛЫЙ. TintColor УМНОЖАЕТ каналы: общий (0,120,140) глушил
-- красный в ноль и половину яркости — под водой в маске было чёрным-черно, что ни
-- делай с блюром. Полной слепоте тёмный тинт можно, маске — нельзя.
local MASKED_TINT       = Color3.fromRGB(205, 235, 245)
local MASKED_BRIGHTNESS = 0.22    -- равномерный подъём яркости; это грейдинг, не свет
local MASKED_CONTRAST   = 0.03
local MASKED_FOG_START  = 8       -- где мгла начинает густеть
local MASKED_FOG_END    = 40      -- дальше этого — сплошная мгла: граница круга
-- ⚠️ ЦВЕТ МГЛЫ СВЕТЛЫЙ, А НЕ «ЦВЕТ ВОДЫ».
-- Тёмно-синяя мгла (16,64,82) съедала дальний план в чёрное даже там, где она
-- ещё редкая: вдаль было не мутно, а темно. Светлая мгла читается как толща воды.
local MASKED_FOG_COLOR  = Color3.fromRGB(90, 150, 170)
--[[ ⚠️ ATMOSPHERE НА ВРЕМЯ МАСКИ УБИРАЕТСЯ ИЗ LIGHTING ЦЕЛИКОМ.
     Пока она там лежит, классический туман (Lighting.Fog*) игнорируется, а её
     собственная плотность даже на максимуме даёт лишь дымку, сквозь которую
     видно на сотни студов — шестой заход, «всё ещё вижу слишком далеко».
     Только Fog* даёт честную сферу: за FogEnd не видно ничего. Поэтому на
     входе в маску атмосфера отцепляется (Parent = nil, объект жив), на выходе
     возвращается на место со всеми своими настройками. ]]
--[[ ⚠️ ДАЛЬНОСТЬ ОБЗОРА ПОД ВОДОЙ — ОДНА РУЧКА: MASKED_WATER_TRANSPARENCY.
     Под поверхностью Roblox рисует собственную мглу по Terrain.WaterTransparency,
     и она сильнее любого тумана из Lighting: FogEnd, Atmosphere и DoF лишь
     подкрашивают и размывают, а КАК ДАЛЕКО видно — решает это число.
     Сверено по скриншотам владельца (восьмой заход):
       0.30 (по умолчанию) — видно на пару метров, «ничего не видно»;
       0.40–0.50 — виден весь океан и острова вдали;
       0.75 — как воздух.
     Зависимость крутая, поэтому шаг правки — сотые: нужно дальше — прибавь
     0.02, ближе — убавь. Остальные MASKED_* числа при этом не трогать.
     На выходе из маски вода возвращается к прежнему значению (restoreFog). ]]
local MASKED_WATER_TRANSPARENCY = 0.34

local dof = Lighting:FindFirstChild("UnderwaterMaskDoF")
if not dof then
	dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "UnderwaterMaskDoF"
	dof.Enabled = false
	dof.Parent = Lighting
end
-- параметры ставим и найденному эффекту: вдруг остался от прежней версии скрипта
dof.FocusDistance = 0
dof.InFocusRadius = MASKED_CLEAR
dof.NearIntensity = 0
dof.FarIntensity = MASKED_FAR_BLUR

-- Туман трогаем с возвратом: запоминаем, что было, и на выходе из-под воды
-- отдаём как забрали — вдруг у сцены свои настройки.
local savedFog = nil

local function applyFog()
	if savedFog then return end
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	savedFog = {
		atmo = atmo,
		density = atmo and atmo.Density or nil,
		haze = atmo and atmo.Haze or nil,
		fogStart = Lighting.FogStart,
		fogEnd = Lighting.FogEnd,
		fogColor = Lighting.FogColor,
		atmoParent = atmo and atmo.Parent or nil,
		waterTransparency = terrain.WaterTransparency,
	}
	if atmo then
		atmo.Parent = nil
	end
	Lighting.FogStart = MASKED_FOG_START
	Lighting.FogEnd = MASKED_FOG_END
	Lighting.FogColor = MASKED_FOG_COLOR
	terrain.WaterTransparency = MASKED_WATER_TRANSPARENCY
end

local function restoreFog()
	if not savedFog then return end
	local s = savedFog
	savedFog = nil
	if s.atmo then
		s.atmo.Density = s.density
		s.atmo.Haze = s.haze
		s.atmo.Parent = s.atmoParent
	end
	Lighting.FogStart = s.fogStart
	Lighting.FogEnd = s.fogEnd
	Lighting.FogColor = s.fogColor
	if s.waterTransparency then terrain.WaterTransparency = s.waterTransparency end
end

local mode = "off"   -- "off" | "full" | "masked"

local function setUnderwater(newMode)
	if newMode == mode then return end
	mode = newMode
	-- сперва снимаем всё от прежнего режима, потом собираем новый
	blur.Size = 0
	colorCorrection.Enabled = false
	dof.Enabled = false
	restoreFog()
	if mode == "off" then return end
	if mode == "full" then
		blur.Size = BLUR_SIZE
		colorCorrection.TintColor = TINT_COLOR
		colorCorrection.Saturation = SATURATION
		colorCorrection.Contrast = CONTRAST
		colorCorrection.Brightness = BRIGHTNESS
		colorCorrection.Enabled = true
	else -- masked: вблизи чисто, вдали мгла
		colorCorrection.TintColor = MASKED_TINT
		colorCorrection.Saturation = MASKED_SATURATION
		colorCorrection.Contrast = MASKED_CONTRAST
		colorCorrection.Brightness = MASKED_BRIGHTNESS
		colorCorrection.Enabled = true
		dof.Enabled = true
		applyFog()
	end
	print("[Underwater] режим:", mode)
end

-- ─── Voxel-based water test ──────────────────────────────────────────────────
-- Sample a tiny region around the camera. Roblox snaps Region3 to the voxel
-- grid, so we expand a touch and ask for a single voxel's worth of data.
local function isPointInWater(position)
	local min = Vector3.new(position.X - 2, position.Y - 2, position.Z - 2)
	local max = Vector3.new(position.X + 2, position.Y + 2, position.Z + 2)
	local region = Region3.new(min, max):ExpandToGrid(VOXEL_RES)

	local ok, materials, occupancies = pcall(function()
		return terrain:ReadVoxels(region, VOXEL_RES)
	end)
	if not ok or not materials then return false, 0 end

	-- ReadVoxels returns 3D arrays; we asked for a 1×1×1 region.
	local material = materials[1] and materials[1][1] and materials[1][1][1]
	local occupancy = occupancies[1] and occupancies[1][1] and occupancies[1][1][1] or 0
	if material == Enum.Material.Water and occupancy > 0.5 then
		return true, occupancy
	end
	return false, 0
end

-- ─── Surface exclusion ───────────────────────────────────────────────────────
-- Even if the camera point is inside a water voxel, we don't want to trigger
-- right at the waterline. Sample a voxel SUBMERGE_DEPTH studs above the camera;
-- if THAT point is also water, the camera is genuinely submerged below the
-- surface. If it isn't, the camera is near the surface and we leave the effect
-- off — no flicker, no half-submerged tinting.
local function isCameraSubmerged()
	local camera = Workspace.CurrentCamera
	if not camera then return false end

	local pos = camera.CFrame.Position
	local hereInWater = isPointInWater(pos)
	if not hereInWater then return false end

	local abovePos = pos + Vector3.new(0, SUBMERGE_DEPTH, 0)
	local aboveInWater = isPointInWater(abovePos)
	return aboveInWater
end

-- ─── МАСКА ДЛЯ НЫРЯНИЯ ───────────────────────────────────────────────────────
-- ⚠️ Маска НЕ отключает подводную слепоту — она даёт РАДИУС ВИДИМОСТИ (MASKED_*
-- выше): чисто в MASKED_CLEAR студах от глаз, дальше мгла. Здесь уже были три
-- неверные версии: полное отключение мути, «прозрачная вода с фонарём» (слишком
-- много обзора) и ровный слабый блюр на весь экран (не видно даже перед носом).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local EquipmentDefs = require(ReplicatedStorage:WaitForChild("EquipmentDefs"))

-- ─── Per-frame check ─────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function()
	if not isCameraSubmerged() then
		setUnderwater("off")
	else
		setUnderwater(EquipmentDefs.hasMask(player) and "masked" or "full")
	end
end)

-- Reset state on respawn so a fresh character can't be left with stuck effects.
player.CharacterAdded:Connect(function()
	setUnderwater("off")
end)