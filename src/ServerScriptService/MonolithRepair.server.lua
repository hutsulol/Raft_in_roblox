-- MonolithRepair.server.lua
-- Phase 1 of the Aquamen Monolith feature — the game's "first interactive".
-- The Monolit_Aquamen model starts BROKEN (broken mesh texture). The player CLICKS it → a repair
-- window opens (client) → paying 5 Log + 5 Leaves swaps the mesh texture to the REPAIRED one, plays
-- a flash + spark burst and lights a soft aqua glow. The repaired state is SHARED (one server-
-- authoritative model) and gates Phase 2 (the diver shop). The starter diver wakes on PURCHASE
-- (DiverShop), not on repair.
--
-- RemoteEvents (created here if missing):
--   MonolithUI     (server→client): "openRepair"/"openShop"/"repaired"/"result"
--   MonolithAction (client→server): "repair"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")

local MODEL_NAME   = "Monolit_Aquamen"
local COST         = { Log = 8, Leaves = 8 } -- баланс §13.6 (было 5/5)
local COST_ORDER   = { "Log", "Leaves" }
local CLICK_DIST   = 32
local AQUA         = Color3.fromRGB(60, 210, 235)
local BROKEN_TEX   = "rbxassetid://106614955770562"
local REPAIRED_TEX = "rbxassetid://131334495741371"

-- ── remotes ──
local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = ReplicatedStorage end
	return r
end
local uiEvent     = ensureRemote("MonolithUI")
local actionEvent = ensureRemote("MonolithAction")

-- ── helpers ──
local function baseParts(model)
	local out = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(out, d) end
	end
	return out
end

local function biggestPart(model)
	local host, best = nil, -1
	for _, p in ipairs(baseParts(model)) do
		local v = p.Size.X * p.Size.Y * p.Size.Z
		if v > best then best, host = v, p end
	end
	return host
end

local function clearFX(model, tag)
	for _, d in ipairs(model:GetDescendants()) do
		if d:GetAttribute(tag) then d:Destroy() end
	end
end

local function fxAnchor(model, tag)
	local host = biggestPart(model)
	if not host then return nil end
	local a = Instance.new("Attachment")
	a.Name = "_MonolithFXAnchor"; a:SetAttribute(tag, true)
	a.WorldPosition = model:GetBoundingBox().Position
	a.Parent = host
	return a
end

-- set the monolith's mesh texture (covers both MeshPart.TextureID and SpecialMesh.TextureId)
local function applyTexture(model, texId)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") then
			d.TextureID = texId
		elseif d:IsA("SpecialMesh") then
			d.TextureId = texId
		end
	end
end

local function applyBroken(model)
	clearFX(model, "_RepairedFX")
	applyTexture(model, BROKEN_TEX)
end

local function applyRepaired(model)
	applyTexture(model, REPAIRED_TEX)
	local a = fxAnchor(model, "_RepairedFX")
	if a then
		local light = Instance.new("PointLight")
		light:SetAttribute("_RepairedFX", true)
		light.Color = AQUA; light.Brightness = 2.5; light.Range = 20; light.Parent = a
	end
end

-- one-shot repair burst (Anchored, unwelded → no effect on the raft assembly)
local function playRepairFX(model)
	local cf = model:GetBoundingBox()
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball; flash.Material = Enum.Material.Neon; flash.Color = AQUA
	flash.Anchored = true; flash.CanCollide = false; flash.CanQuery = false; flash.CastShadow = false
	flash.Size = Vector3.new(6, 6, 6); flash.CFrame = cf; flash.Transparency = 0.1; flash.Parent = Workspace
	TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(46, 46, 46), Transparency = 1 }):Play()
	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Color = ColorSequence.new(AQUA, Color3.fromRGB(255, 255, 255)); burst.LightEmission = 0.8
	burst.Size = NumberSequence.new(1.4, 0.1); burst.Lifetime = NumberRange.new(0.5, 1.0)
	-- server-side :Emit() does NOT replicate to clients — burst via a short enabled Rate window
	burst.Speed = NumberRange.new(20, 40); burst.SpreadAngle = Vector2.new(180, 180)
	burst.Rate = 280
	burst.Parent = flash
	task.delay(0.25, function() burst.Enabled = false end)
	Debris:AddItem(flash, 1.2)
end

-- ── model wiring ──
local currentModel = nil
local function isRepaired(model) return model:GetAttribute("Repaired") == true end

local function nearModel(plr, model)
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	-- меряем до БЛИЖАЙШЕЙ части модели, а не до центра bounding box: у
	-- крупной/смещённой модели центр может оказаться далеко от игрока,
	-- хотя он стоит вплотную (из-за этого выбивало «подойди ближе»)
	local pos = hrp.Position
	local best = math.huge
	for _, p in ipairs(baseParts(model)) do
		local d = (p.Position - pos).Magnitude
		if d < best then best = d end
	end
	return best <= (CLICK_DIST + 16)
end

local function onClick(plr, model)
	if not isRepaired(model) then
		uiEvent:FireClient(plr, "openRepair", COST, COST_ORDER)   -- broken → repair window
	elseif _G.OpenDiverShop then
		-- repaired → the UPGRADE menu (new design). The delivery timer/skip window is parked until we
		-- decide where the timer lives in the new UI (_G.OpenDiverStatus still exists for that).
		_G.OpenDiverShop(plr)
	else
		uiEvent:FireClient(plr, "openShop")                      -- fallback stub
	end
end

local function setupModel(model)
	if isRepaired(model) then
		applyRepaired(model)
	else
		model:SetAttribute("Repaired", false)
		applyBroken(model)
	end
	local host = biggestPart(model)
	if host and not host:FindFirstChildOfClass("ClickDetector") then
		local cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = CLICK_DIST
		cd.Parent = host
		cd.MouseClick:Connect(function(plr) onClick(plr, model) end)
	end
end

local function tryInit(inst)
	if currentModel then return end
	if inst:IsA("Model") and inst.Name == MODEL_NAME then
		currentModel = inst
		setupModel(inst)
	end
end

for _, d in ipairs(Workspace:GetDescendants()) do tryInit(d) end
Workspace.DescendantAdded:Connect(tryInit)

-- expose the monolith + its repaired state to the diver systems (Phase 2/3)
_G.GetMonolith = function() return currentModel end
_G.IsMonolithRepaired = function() return currentModel ~= nil and isRepaired(currentModel) end

-- Восстановление статуса «починен» из сейва (RaftSaveSystem). Ставит
-- атрибут, применяет вид починенного и будит дайвера. Возвращает true,
-- если модель уже найдена (иначе загрузчик подождёт и повторит).
_G.RestoreMonolithRepaired = function()
	if not currentModel then return false end
	currentModel:SetAttribute("Repaired", true)
	applyRepaired(currentModel)
	if _G.OnMonolithRepaired then pcall(_G.OnMonolithRepaired) end
	return true
end

-- ── repair request ──
actionEvent.OnServerEvent:Connect(function(plr, action)
	-- во время катсцены взаимодействие запрещено (флаг ставит IslandClearSystem)
	if plr:GetAttribute("InCutscene") then uiEvent:FireClient(plr, "result", "cutscene"); return end
	local model = currentModel
	if action ~= "repair" or not model or not model.Parent then return end
	if isRepaired(model) then uiEvent:FireClient(plr, "result", "already"); return end
	if not nearModel(plr, model) then uiEvent:FireClient(plr, "result", "tooFar"); return end
	if not (_G.GetInventory and _G.RemoveResourceFromInventory) then
		uiEvent:FireClient(plr, "result", "error"); return
	end
	local inv = _G.GetInventory(plr) or {}
	local haveLog, haveLeaves = inv["Log"] or 0, inv["Leaves"] or 0
	if haveLog >= COST.Log and haveLeaves >= COST.Leaves then
		_G.RemoveResourceFromInventory(plr, "Log", COST.Log)
		_G.RemoveResourceFromInventory(plr, "Leaves", COST.Leaves)
		-- та же забытая строка, что и в магазине дайвера: списание правит только
		-- серверную таблицу, показать это игроку — дело SendInventory
		if _G.SendInventory then _G.SendInventory(plr) end
		-- квест «оживи дайвера» закрывается ровно здесь
		if _G.OnQuestEvent then pcall(_G.OnQuestEvent, plr, "monolith:repaired", 1) end
		model:SetAttribute("Repaired", true)
		applyRepaired(model)
		playRepairFX(model)
		uiEvent:FireAllClients("repaired")
		uiEvent:FireClient(plr, "result", "success")
		-- repairing the monolith is what WAKES the diver (he stands up and starts working)
		if _G.OnMonolithRepaired then pcall(_G.OnMonolithRepaired) end
	else
		uiEvent:FireClient(plr, "result", "notEnough", {
			Log = math.max(0, COST.Log - haveLog),
			Leaves = math.max(0, COST.Leaves - haveLeaves),
		})
	end
end)

print("[MonolithRepair] ready (waiting for " .. MODEL_NAME .. ")")
