-- DestructibleSystem.server.lua
-- Per-part destruction for tagged Models. Tag a Model with the
-- "Destructible" CollectionService tag and every BasePart inside it
-- becomes individually choppable: an axe hit damages only the
-- specific part the client clicked, and once that part's PartHealth
-- hits zero it snaps off the assembly, gets a small impulse + spin,
-- fades out, and is removed. When the model has no parts left we
-- destroy the wrapper Model too.
--
-- Model-level attribute overrides (optional):
--   PartHealth     (number) — applied to every BasePart at init time.
--                            Override per-part by setting the same
--                            attribute on the part itself.
--   DamagePerHit   (number) — overrides DEFAULT_DAMAGE_PER_HIT.
--   AxeOnly        (bool)   — when true (default) only axe-class
--                            Tools can damage; set false to let any
--                            equipped Tool work.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local TAG = "Destructible"
local DEFAULT_PART_HEALTH = 30
local DEFAULT_DAMAGE_PER_HIT = 10
local HIT_RANGE = 18
local HIT_COOLDOWN = 0.45
local BREAK_FADE_TIME = 1.2
local BREAK_DEBRIS_TIME = 2.0

local AXE_TOOLS = {
	["Stone_Axe"] = true,
	["Axe"] = true,
}

local hitEvent = ReplicatedStorage:FindFirstChild("DestructibleHit")
if not hitEvent then
	hitEvent = Instance.new("RemoteEvent")
	hitEvent.Name = "DestructibleHit"
	hitEvent.Parent = ReplicatedStorage
end

local lastHitTime = {}

-- ─── Init tagged models ────────────────────────────────────────────
local function initPart(part, modelHealth)
	if not part:IsA("BasePart") then return end
	if part:GetAttribute("PartHealth") == nil then
		part:SetAttribute("PartHealth", modelHealth)
	end
end

local function pickPrimary(model)
	if model.PrimaryPart then return model.PrimaryPart end
	local largest, largestVol = nil, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > largestVol then
				largest = d
				largestVol = v
			end
		end
	end
	return largest
end

-- Build a star of WeldConstraints from `primary` to every other
-- BasePart so the model stays together as one rigid assembly when we
-- later release the anchor. We skip parts that already share a weld
-- with the primary so author-supplied welds aren't duplicated.
local function weldStar(model, primary)
	if not primary then return end
	local connected = { [primary] = true }
	for _, w in model:GetDescendants() do
		if w:IsA("WeldConstraint") or w:IsA("Weld") then
			if w.Part0 == primary and w.Part1 then connected[w.Part1] = true
			elseif w.Part1 == primary and w.Part0 then connected[w.Part0] = true end
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not connected[d] then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = d
			weld.Parent = primary
		end
	end
end

local function initModel(model)
	if not model:IsA("Model") then return end
	local modelHealth = model:GetAttribute("PartHealth") or DEFAULT_PART_HEALTH
	for _, descendant in model:GetDescendants() do
		initPart(descendant, modelHealth)
	end
	model.DescendantAdded:Connect(function(descendant)
		initPart(descendant, modelHealth)
	end)

	-- Hold the assembly together with a star of welds rooted at the
	-- primary. The author can leave every part Anchored — once the
	-- first chunk is broken off we release the primary's anchor and
	-- the rest of the model hangs together via these welds, falling
	-- naturally onto whatever supports it.
	local primary = pickPrimary(model)
	if primary then
		if not model.PrimaryPart then
			model.PrimaryPart = primary
		end
		weldStar(model, primary)
	end
end

for _, model in CollectionService:GetTagged(TAG) do
	initModel(model)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(initModel)

-- ─── Break a part off the assembly ──────────────────────────────────
local function snapWelds(part)
	for _, d in part:GetDescendants() do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D")
			or d:IsA("Snap") or d:IsA("Glue") then
			d:Destroy()
		end
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if model then
		for _, d in model:GetDescendants() do
			if (d:IsA("WeldConstraint") or d:IsA("Weld"))
				and (d.Part0 == part or d.Part1 == part) then
				d:Destroy()
			end
		end
	end
end

local function breakPart(part)
	snapWelds(part)
	part.Anchored = false
	part.CanCollide = true

	local mass = math.max(part.AssemblyMass, 0.5)
	local impulse = Vector3.new(
		math.random(-25, 25),
		math.random(35, 60),
		math.random(-25, 25)
	) * mass
	part:ApplyImpulse(impulse)
	part.AssemblyAngularVelocity = Vector3.new(
		math.random(-6, 6),
		math.random(-6, 6),
		math.random(-6, 6)
	)

	local fade = TweenService:Create(part, TweenInfo.new(BREAK_FADE_TIME), { Transparency = 1 })
	fade:Play()
	Debris:AddItem(part, BREAK_DEBRIS_TIME)
end

local function modelHasIntactParts(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not d:GetAttribute("PartBroken") then
			return true
		end
	end
	return false
end

-- After a break, any intact part that no longer shares a
-- WeldConstraint with another intact part is effectively floating
-- debris — chunks dangling off a primary that was just chopped, or
-- bits the player snapped loose in a cluster. Cascade the same fade-
-- and-destroy cycle on them (with a small random stagger) so the
-- ground doesn't end up littered with leftover pieces.
local function cascadeLooseParts(model)
	local intact = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not d:GetAttribute("PartBroken") then
			intact[d] = true
		end
	end

	local connected = {}
	for _, w in model:GetDescendants() do
		if (w:IsA("WeldConstraint") or w:IsA("Weld")) and w.Part0 and w.Part1 then
			if intact[w.Part0] and intact[w.Part1] then
				connected[w.Part0] = true
				connected[w.Part1] = true
			end
		end
	end

	for partInstance in pairs(intact) do
		if not connected[partInstance] then
			partInstance:SetAttribute("PartBroken", true)
			local p = partInstance
			task.spawn(function()
				task.wait(math.random() * 0.25 + 0.05)
				if p.Parent then
					breakPart(p)
				end
			end)
		end
	end
end

-- ─── Hit handler ───────────────────────────────────────────────────
hitEvent.OnServerEvent:Connect(function(player, model, part)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return end
	if not CollectionService:HasTag(model, TAG) then return end
	if not part:IsDescendantOf(model) then return end
	if part:GetAttribute("PartBroken") then return end

	local char = player.Character
	if not char then return end

	local tool = char:FindFirstChildWhichIsA("Tool")
	local axeOnly = model:GetAttribute("AxeOnly")
	if axeOnly == nil then axeOnly = true end
	if axeOnly then
		if not tool or not AXE_TOOLS[tool.Name] then return end
	else
		if not tool then return end
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if (hrp.Position - part.Position).Magnitude > HIT_RANGE then return end

	local now = tick()
	local prev = lastHitTime[player] or 0
	if now - prev < HIT_COOLDOWN then return end
	lastHitTime[player] = now

	local damage = model:GetAttribute("DamagePerHit") or DEFAULT_DAMAGE_PER_HIT
	local hp = part:GetAttribute("PartHealth")
	if typeof(hp) ~= "number" then
		hp = model:GetAttribute("PartHealth") or DEFAULT_PART_HEALTH
	end
	hp = hp - damage

	if hp > 0 then
		part:SetAttribute("PartHealth", hp)
		return
	end

	-- First broken chunk also releases the rest of the assembly so
	-- the remaining parts don't hang frozen in mid-air. They're still
	-- bound together by the init-time WeldConstraint star, so gravity
	-- treats them as one rigid body that rests on whatever's below.
	if not model:GetAttribute("Released") then
		model:SetAttribute("Released", true)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= part and not d:GetAttribute("PartBroken") then
				d.Anchored = false
			end
		end
	end

	part:SetAttribute("PartBroken", true)
	breakPart(part)
	cascadeLooseParts(model)

	task.delay(BREAK_DEBRIS_TIME + 0.5, function()
		if model.Parent and not modelHasIntactParts(model) then
			model:Destroy()
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastHitTime[player] = nil
end)

print("[DestructibleSystem] Loaded — tag models with " .. TAG)
