-- FruitBushSystem.server.lua
-- Hand-harvest fruit bushes (currently just the Pineapple). The
-- player presses E near a fruit-bearing model and the server grants
-- a randomised payload + one seed of the matching kind, then puts
-- the bush on a respawn cooldown that hides its visible fruit
-- meshes until the timer elapses.
--
-- Adding a new fruit bush is a one-entry change in HARVESTABLE below
-- plus a matching client hint in FruitBushClient.client.lua.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Per-bush harvest schema. Match keys are model Name fragments —
-- "PineApple leaves" in workspace matches via the leading "PineApple"
-- so renamed siblings (PineApple leaves, PineApple leaves2, …) all
-- share the same rule without per-instance config.
local HARVESTABLE = {
	["PineApple"] = {
		fruitName  = "Pineapple",
		seedName   = "Pineapple_Seed",
		fruitMin   = 1,
		fruitMax   = 2,
		seedCount  = 1,
		cooldown   = 60,  -- seconds before the bush bears fruit again
	},
}

-- Tag every harvestable bush in workspace (Studio-placed or spawner-
-- spawned) so the client can find them via CollectionService instead
-- of doing a full workspace descendant walk every Heartbeat. Bushes
-- can be nested arbitrarily — the user authors them inside Island_1,
-- inside a Trees folder, anywhere — and the tag survives clones.
local HARVESTABLE_TAG = "HarvestableFruitBush"

local function tagIfBush(inst)
	if not inst or not inst:IsA("Model") then return end
	for prefix in pairs(HARVESTABLE) do
		if string.find(inst.Name, prefix, 1, true) then
			if not CollectionService:HasTag(inst, HARVESTABLE_TAG) then
				CollectionService:AddTag(inst, HARVESTABLE_TAG)
			end
			return
		end
	end
end

-- Initial pass + live watcher. workspace.DescendantAdded fires for
-- everything (Island_1 children, IslandSpawner clones, anything the
-- user drops in via Studio), so we don't need a per-island hook.
for _, descendant in workspace:GetDescendants() do
	tagIfBush(descendant)
end
workspace.DescendantAdded:Connect(tagIfBush)

local PICKUP_RANGE = 12  -- studs — must agree with the client hint

-- ─── RemoteEvent setup ───
local harvestEvent = ReplicatedStorage:FindFirstChild("HarvestFruit")
if not harvestEvent then
	harvestEvent = Instance.new("RemoteEvent")
	harvestEvent.Name = "HarvestFruit"
	harvestEvent.Parent = ReplicatedStorage
end

-- Wait for inventory globals before accepting any requests so the
-- first player can't fire before the grant helper exists.
while not _G.AddResourceToInventory do
	task.wait(0.1)
end

local function findHarvestRule(model)
	if not model or not model:IsA("Model") then return nil end
	local n = model.Name
	for prefix, rule in pairs(HARVESTABLE) do
		if string.find(n, prefix, 1, true) then return rule end
	end
	return nil
end

-- Hide / show the fruit child meshes during cooldown. Pineapple
-- models typically nest the visible fruit under a sub-Model or named
-- BasePart — we soft-search both so the script keeps working across
-- authoring conventions.
local function setFruitVisible(bush, visible)
	for _, descendant in bush:GetDescendants() do
		if descendant:IsA("BasePart") then
			local nameL = descendant.Name:lower()
			if nameL:find("fruit") or nameL:find("pineapple") or nameL:find("banana") or nameL:find("coconut") then
				descendant.Transparency = visible and 0 or 1
				descendant.CanCollide   = visible and descendant.CanCollide or false
				descendant.CanQuery     = visible and descendant.CanQuery   or false
			end
		end
	end
end

harvestEvent.OnServerEvent:Connect(function(player, target)
	if typeof(target) ~= "Instance" then return end
	if not target:IsDescendantOf(workspace) then return end

	-- Walk up to the actual bush Model (the client might fire with a
	-- raycast-hit leaf BasePart).
	local bush = target
	local rule = findHarvestRule(bush)
	while not rule and bush.Parent do
		bush = bush.Parent
		rule = findHarvestRule(bush)
		if bush == workspace then break end
	end
	if not rule then return end

	if bush:GetAttribute("FruitCooldown") then return end

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Distance check using the bush's pivot — robust to ragdolled or
	-- multi-part models.
	local bushPos = bush:GetPivot().Position
	if (hrp.Position - bushPos).Magnitude > PICKUP_RANGE then return end

	-- Mark cooldown BEFORE granting items so a double-fire from the
	-- client can't double-dip.
	bush:SetAttribute("FruitCooldown", true)
	setFruitVisible(bush, false)

	local fruitAmount = math.random(rule.fruitMin, rule.fruitMax)
	_G.AddResourceToInventory(player, rule.fruitName, fruitAmount, bushPos)
	if rule.seedCount > 0 then
		-- Seeds go into the player's leaf bag rather than the main
		-- inventory. Without a bag they spill onto the ground.
		if typeof(_G.AddSeedToBag) == "function" then
			_G.AddSeedToBag(player, rule.seedName, rule.seedCount, bushPos)
		else
			_G.AddResourceToInventory(player, rule.seedName, rule.seedCount, bushPos)
		end
	end
	if _G.OnQuestResource then
		pcall(_G.OnQuestResource, player, rule.fruitName, fruitAmount)
	end

	task.delay(rule.cooldown, function()
		if not bush or not bush.Parent then return end
		bush:SetAttribute("FruitCooldown", false)
		bush:SetAttribute("FruitCooldown", nil)
		setFruitVisible(bush, true)
	end)
end)
